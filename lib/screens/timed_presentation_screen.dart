import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui'; // Needed for ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:deepgram_speech_to_text/deepgram_speech_to_text.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../services/grammar_api_service.dart';
import 'grammar_report_screen.dart';
import 'fluency_screen.dart';

final stt = dotenv.env['STT'];

class SttTest extends StatefulWidget {
  const SttTest({super.key});

  @override
  State<SttTest> createState() => _SttTestState();
}

class _SttTestState extends State<SttTest> with TickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  Deepgram? _deepgram;
  DeepgramLiveListener? _liveListener;
  StreamSubscription? _deepgramSubscription;

  final TextEditingController _textController = TextEditingController();
  late ScrollController _scrollController = ScrollController(); // NEW: For auto-scrolling

  String _fullTranscript = '';
  String _currentSegment = '';

  String? _recordedFilePath;
  String? _lastSuccessfulRecordingPath;
  StreamSubscription<List<int>>? _audioStreamSubscription;
  IOSink? _audioFileSink;

  bool _isListening = false;
  bool _isAnalyzing = false;

  // --- Timer Logic ---
  Timer? _timer;
  int _elapsedSeconds = 0;
  int _targetDurationSeconds = 30; // Default 30s

  @override
  void initState() {
    super.initState();
    _deepgram = Deepgram(stt!);
    _textController.text = 'Your speech will appear here...';
    _scrollController = ScrollController(); // NEW: Initialize
  }

  // --- Logic ---

  Future<bool> _checkPermission() async {
    PermissionStatus status = await Permission.microphone.request();
    return status.isGranted;
  }

  void _startTimer() {
    _elapsedSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });

      if (_elapsedSeconds >= _targetDurationSeconds) {
        _handleAutoStop();
      }
    });
  }

  void _handleAutoStop() async {
    _timer?.cancel();
    await _stopListening();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Time's up! Generating report..."),
          backgroundColor: Color(0xFF6C63FF),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _generateCombinedReport();
    }
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  String _formatTime(int totalSeconds) {
    int remaining = _targetDurationSeconds - totalSeconds;
    if (remaining < 0) remaining = 0;
    int minutes = remaining ~/ 60;
    int seconds = remaining % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _getDurationLabel(int seconds) {
    if (seconds < 60) {
      return "${seconds}s";
    } else {
      return "${seconds ~/ 60} min";
    }
  }

  void _showDurationPicker() {
    if (_isListening) return;

    final List<int> options = [15, 30, 60, 120, 180, 300];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            const Text("Select Duration", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2E1065))),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: options.map((seconds) {
                bool isSelected = _targetDurationSeconds == seconds;
                return ChoiceChip(
                  label: Text(_getDurationLabel(seconds)),
                  selected: isSelected,
                  selectedColor: const Color(0xFF6C63FF),
                  backgroundColor: const Color(0xFFF5F3FF),
                  labelStyle: TextStyle(color: isSelected ? Colors.white : const Color(0xFF6C63FF)),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(() {
                        _targetDurationSeconds = seconds;
                        _elapsedSeconds = 0;
                      });
                      Navigator.pop(context);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _startListening() async {
    if (_isListening) return;

    if (!await _checkPermission()) {
      _textController.text = 'Microphone permission denied.';
      return;
    }

    setState(() {
      if (_fullTranscript.isEmpty || _fullTranscript == 'Your speech will appear here...') {
        _fullTranscript = '';
        _textController.clear();
      }
      _currentSegment = '';
      _isListening = true;
    });

    _startTimer();

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordedFilePath = '${dir.path}/recording_$timestamp.wav';

      final audioFile = File(_recordedFilePath!);
      if (await audioFile.exists()) {
        await audioFile.delete();
      }

      _audioFileSink = audioFile.openWrite();
      _writeWavHeader(_audioFileSink!, 0);

      Map<String, dynamic> queryParams = {
        'model': 'nova-2-general',
        'punctuate': true,
        'interim_results': true,
        'encoding': 'linear16',
        'sample_rate': 16000,
      };

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      final broadcastStream = stream.asBroadcastStream();

      _audioStreamSubscription = broadcastStream.listen((audioData) {
        _audioFileSink?.add(audioData);
      });

      _liveListener = _deepgram!.listen.liveListener(
        broadcastStream,
        queryParams: queryParams,
      );

      _deepgramSubscription = _liveListener!.stream.listen((result) {
        if (result.transcript != null && result.transcript!.isNotEmpty) {
          setState(() {
            if (result.isFinal ?? false) {
              _fullTranscript += (_fullTranscript.isEmpty ? '' : ' ') + result.transcript!;
              _currentSegment = '';
            } else {
              _currentSegment = result.transcript!;
            }
            _textController.text = _fullTranscript +
                (_currentSegment.isEmpty ? '' : (_fullTranscript.isEmpty ? '' : ' ') + _currentSegment);
            _textController.selection = TextSelection.fromPosition(
              TextPosition(offset: _textController.text.length),
            );
          });
          // NEW: Auto-scroll to bottom after text update
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }
      }, onError: (error) {
        setState(() => _textController.text = 'Error: $error');
      });

      _liveListener!.start();

    } catch (e) {
      setState(() {
        _textController.text = 'Error: $e';
        _isListening = false;
      });
      _stopTimer();
    }
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;

    setState(() => _isListening = false);
    _stopTimer();

    try {
      await _recorder.stop();
      await _deepgramSubscription?.cancel();
      _deepgramSubscription = null;
      _liveListener?.close();
      _liveListener = null;
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;

      if (_audioFileSink != null) {
        await _audioFileSink!.flush();
        await _audioFileSink!.close();
        _audioFileSink = null;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (_currentSegment.isNotEmpty) {
        _fullTranscript += (_fullTranscript.isEmpty ? '' : ' ') + _currentSegment;
        _currentSegment = '';
      }

      setState(() => _textController.text = _fullTranscript);

      if (_recordedFilePath != null) {
        await _finalizeWavFile(_recordedFilePath!);
        _lastSuccessfulRecordingPath = _recordedFilePath;
      }
    } catch (e) {
      print('Error stopping listener: $e');
      setState(() => _isListening = false);
    }
  }

  Future<void> _finalizeWavFile(String filePath) async {
    try {
      final audioFile = File(filePath);
      if (await audioFile.exists()) {
        final fileSize = await audioFile.length();
        if (fileSize > 44) {
          final bytes = await audioFile.readAsBytes();
          final header = _getWavHeaderBytes(fileSize - 44);
          for (int i = 0; i < 44 && i < header.length; i++) {
            bytes[i] = header[i];
          }
          await audioFile.writeAsBytes(bytes);
        }
      }
    } catch (e) {
      print('Error finalizing WAV file: $e');
    }
  }

  List<int> _getWavHeaderBytes(int dataSize) {
    return [
      0x52, 0x49, 0x46, 0x46, ...(_int32ToBytes(dataSize + 36)),
      0x57, 0x41, 0x56, 0x45, 0x66, 0x6D, 0x74, 0x20,
      0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
      0x80, 0x3E, 0x00, 0x00, 0x00, 0x7D, 0x00, 0x00,
      0x02, 0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61,
      ...(_int32ToBytes(dataSize)),
    ];
  }

  void _writeWavHeader(IOSink sink, int dataSize) {
    sink.add(_getWavHeaderBytes(dataSize));
  }

  List<int> _int32ToBytes(int value) {
    return [value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF, (value >> 24) & 0xFF];
  }

  void _generateCombinedReport() async {
    final textToAnalyze = _textController.text.trim();
    final pathToUse = _recordedFilePath ?? _lastSuccessfulRecordingPath;

    if (textToAnalyze.isEmpty || textToAnalyze.startsWith('Your speech')) {
      _showErrorSnackBar('Please record some text first!');
      return;
    }

    if (pathToUse == null) {
      _showErrorSnackBar('No recording found. Please record audio first!');
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final grammarResult = await GrammarApiService.analyzeText(textToAnalyze);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UnifiedReportScreen(
              grammarResult: grammarResult,
              audioPath: pathToUse,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar('Error analyzing text: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _textController.dispose();
    _scrollController.dispose(); // NEW: Dispose
    _audioFileSink?.close();
    super.dispose();
  }

  // --- UI BUILD ---

  @override
  Widget build(BuildContext context) {
    double progress = (_targetDurationSeconds - _elapsedSeconds) / _targetDurationSeconds;
    if (progress < 0) progress = 0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "Presentation Practice",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          // THEME: Blue -> Purple Gradient from "Lingua Franca" Login Screen
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF4FACFE), // Login Light Blue
              Color(0xFF8A4FFF), // Login Purple
            ],
          ),
        ),
        child: Stack(
          children: [
            // Decorative Circle
            Positioned(
              top: -80,
              right: -50,
              child: Container(
                width: 250, height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        children: [
                          // 1. TOPIC CARD
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Column(
                              children: [
                                Text(
                                  "TOPIC",
                                  style: TextStyle(
                                    color: Color(0xFF6C63FF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  "Start talking about any topic",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF2E1065),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 35),

                          // 2. TIMER (Gold Accent)
                          SizedBox(
                            height: 190, width: 190,
                            child: CustomPaint(
                              painter: TimerPainter(
                                progress: progress,
                                color: const Color(0xFF7630E1), // Gold from Dashboard Icons
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _formatTime(_elapsedSeconds),
                                      style: const TextStyle(
                                          fontSize: 56,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          letterSpacing: -1.5,
                                          shadows: [Shadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))]
                                      ),
                                    ),
                                    Text(
                                      "Remaining",
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 25),

                          // 3. DURATION PILL
                          GestureDetector(
                            onTap: _showDurationPicker,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.timer_outlined, size: 16, color: Colors.white),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Target: ${_getDurationLabel(_targetDurationSeconds)}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withValues(alpha: 0.8), size: 18),
                                  ]
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Recording Pill
                          AnimatedOpacity(
                            opacity: _isListening ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.redAccent.withValues(alpha: 0.4), blurRadius: 8)],
                              ),
                              child: const Text(
                                "REC",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // 4. TRANSCRIPT BOX (Fixed Clipping Issue)
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(24),
                                  topRight: Radius.circular(24),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.notes_rounded, size: 16, color: Colors.grey[400]),
                                          const SizedBox(width: 8),
                                          Text(
                                            "LIVE TRANSCRIPT",
                                            style: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: _textController,
                                        scrollController: _scrollController, // NEW: Add scroll controller
                                        maxLines: null,
                                        expands: true,
                                        readOnly: true,
                                        textAlignVertical: TextAlignVertical.top, // FIX: Forces text to start at top
                                        style: const TextStyle(
                                          fontSize: 18,
                                          height: 1.6,
                                          color: Color(0xFF1F2937),
                                          fontWeight: FontWeight.w500,
                                        ),
                                        decoration: InputDecoration(
                                          border: InputBorder.none,
                                          contentPadding: const EdgeInsets.all(24), // FIX: Prevents edge clipping
                                          hintText: "Start speaking...",
                                          hintStyle: TextStyle(color: Colors.grey[300]),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // --- BOTTOM CONTROLS ---
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 12),
                    child: _buildBottomControls(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    // 1. Analyzing
    if (_isAnalyzing) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C63FF))),
            SizedBox(width: 12),
            Text("Analyzing speech...", style: TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    // 2. Recording
    if (_isListening) {
      return Center(
        child: GestureDetector(
          onTap: _stopListening,
          child: Container(
            height: 72, width: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(Icons.stop_rounded, color: Colors.white, size: 36),
          ),
        ),
      );
    }

    // 3. Retry / Analysis (After Recording)
    if (_lastSuccessfulRecordingPath != null && !_isListening) {
      return Row(
        children: [
          // Retry
          InkWell(
            onTap: _startListening,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 56, width: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Icon(Icons.refresh_rounded, color: Color(0xFF4B5563)),
            ),
          ),
          const SizedBox(width: 16),
          // View Analysis Button
          Expanded(
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _generateCombinedReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "View Analysis",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // 4. Idle (Start Button)
    return Center(
      child: GestureDetector(
        onTap: _startListening,
        child: Container(
          height: 72, width: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF), // Brand Purple
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}

// --- Timer Painter ---
class TimerPainter extends CustomPainter {
  final double progress;
  final Color color;
  TimerPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    Paint bg = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    Paint fg = Paint()
      ..color = color
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    Offset c = Offset(size.width / 2, size.height / 2);
    double r = min(size.width / 2, size.height / 2);

    canvas.drawCircle(c, r, bg);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -pi / 2, 2 * pi * progress, false, fg);
  }

  @override
  bool shouldRepaint(TimerPainter old) => old.progress != progress || old.color != color;
}

class UnifiedReportScreen extends StatelessWidget {
  final GrammarAnalysisResult grammarResult;
  final String audioPath;

  const UnifiedReportScreen({
    super.key,
    required this.grammarResult,
    required this.audioPath,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text(
            "Performance Analysis",
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: const BackButton(color: Colors.black87),
          bottom: const TabBar(
            labelColor: Color(0xFF6C63FF),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFF6C63FF),
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            tabs: [
              Tab(text: "Grammar"),
              Tab(text: "Fluency"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            GrammarReportScreen(result: grammarResult),
            FluencyScreen(audioPath: audioPath),
          ],
        ),
      ),
    );
  }
}