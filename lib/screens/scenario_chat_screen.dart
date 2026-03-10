import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:deepgram_speech_to_text/deepgram_speech_to_text.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/scenario.dart';
import '../services/ollama_api_service.dart';
import '../services/fluency_api_service.dart';
import '../services/grammar_api_service.dart';
import '../services/tts_api_service.dart';
import '../services/my_audio_source.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'unified_report_screen.dart';

class ScenarioChatScreen extends StatefulWidget {
  final Scenario scenario;

  const ScenarioChatScreen({super.key, required this.scenario});

  @override
  State<ScenarioChatScreen> createState() => _ScenarioChatScreenState();
}

class _ScenarioChatScreenState extends State<ScenarioChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isFinished = false;

  final Color primaryPurple = const Color(0xFF8A48F0);
  final Color secondaryPurple = const Color(0xFFD9BFFF);
  final Color softBackground = const Color(0xFFF7F7FA);
  final Color textDark = const Color(0xFF101828);
  final Color textGrey = const Color(0xFF667085);

  // STT variables
  final AudioRecorder _recorder = AudioRecorder();
  late Deepgram _deepgram;
  DeepgramLiveListener? _liveListener;
  StreamSubscription? _deepgramSubscription;
  bool _isListening = false;
  String _fullTranscript = '';
  String _currentSegment = '';

  // TTS variables
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _selectedAccent = 'american';
  bool _isTtsPlaying = false; // True while AI audio is playing — blocks mic to prevent audio session conflict

  // Background Analysis Variables
  IOSink? _audioFileSink;
  StreamSubscription<List<int>>? _audioStreamSubscription;
  String? _currentTurnAudioPath;
  final List<Map<String, dynamic>> _turnFluencyResults = [];
  final List<Future<void>> _activeFluencyTasks = []; // Track pending background tasks
  final List<String> _userTranscripts = [];

  @override
  void initState() {
    super.initState();
    // Initialize system context
    _messages.add({
      "role": "system",
      "content": widget.scenario.systemPrompt,
      "isVisible": false,
    });

    // Add initial greeting from AI
    _messages.add({
      "role": "assistant",
      "content": widget.scenario.initialGreeting,
      "isVisible": true,
      "timestamp": DateTime.now(),
    });

    final sttKey = dotenv.env['STT'] ?? '';
    _deepgram = Deepgram(sttKey);

    _initAudioSession().then((_) {
      // Pre-warm the Grammar API Cloud Run instance in the background so it's
      // ready by the time the conversation ends. Fire-and-forget; errors are ignored.
      GrammarApiService.analyzeText('warmup').catchError((_) {});

      // Play the initial AI greeting after the audio session is fully ready.
      // NOTE: _isTtsPlaying is managed exclusively inside _playAiResponse via
      // try/finally. Do NOT add a playerStateStream listener here — it fires
      // immediately with playing=false (player is idle) and would race-reset the flag.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _playAiResponse(widget.scenario.initialGreeting);
        }
      });
    });
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
      androidWillPauseWhenDucked: true,
    ));
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    if (_isListening) {
      await _stopListening();
    }

    final userMessage = text.trim();
    
    // Add to user transcripts so it gets analyzed by Grammar API
    _userTranscripts.add(userMessage);

    setState(() {
      _messages.add({
        "role": "user",
        "content": userMessage,
        "isVisible": true,
        "timestamp": DateTime.now(),
      });
      _isLoading = true;
    });

    _controller.clear();
    _scrollToBottom();

    // Prepare history for Ollama
    List<Map<String, String>> apiMessages =
        _messages.map((msg) {
          return {
            "role": msg["role"] as String,
            "content": msg["content"] as String,
          };
        }).toList();

    try {
      String response = await OllamaApiService.getResponse(apiMessages);

      bool isFinished = false;
      if (response.contains('[END_CONVERSATION]')) {
        response = response.replaceAll('[END_CONVERSATION]', '').trim();
        isFinished = true;
      }

      setState(() {
        if (response.isNotEmpty) {
          _messages.add({
            "role": "assistant",
            "content": response,
            "isVisible": true,
            "timestamp": DateTime.now(),
          });
          
          // trigger TTS playback silently
          _playAiResponse(response);
        }
        _isLoading = false;
        if (isFinished) {
          _endConversation();
        }
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add({
          "role": "system_error",
          "content": "Error: ${e.toString()}",
          "isVisible": true,
          "timestamp": DateTime.now(),
        });
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _playAiResponse(String text) async {
    if (mounted) setState(() => _isTtsPlaying = true);
    try {
      final audioBytes = await TtsApiService.synthesize(
        text: text,
        accent: _selectedAccent,
      );

      // Load bytes into just_audio player
      await _audioPlayer.setAudioSource(MyAudioSource(audioBytes));
      await _audioPlayer.play();

      // Wait for playback to actually finish before releasing the lock
      await _audioPlayer.playerStateStream.firstWhere(
        (s) => s.processingState == ProcessingState.completed || !s.playing,
      );
    } catch (e) {
      debugPrint('[TTS Error] Failed to generate/play audio: $e');
      // Don't show a snackbar for TTS failures — the conversation should still work
    } finally {
      if (mounted) setState(() => _isTtsPlaying = false);
    }
  }

  Future<bool> _checkPermission() async {
    PermissionStatus status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _toggleRecording() async {
    if (_isListening) {
      await _stopListening();
    } else {
      // Bug fix: Block mic while AI is speaking to prevent audio session conflict
      if (_isTtsPlaying) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please wait for AI to finish speaking first.'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!await _checkPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    setState(() {
      _isListening = true;
      _fullTranscript = '';
      _currentSegment = '';
      // Do NOT clear controller here so they don't lose typed text if they accidentally hit mic
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentTurnAudioPath = '${dir.path}/scenario_turn_$timestamp.wav';

      final audioFile = File(_currentTurnAudioPath!);
      if (await audioFile.exists()) {
        await audioFile.delete();
      }

      _audioFileSink = audioFile.openWrite();
      _writeWavHeader(_audioFileSink!, 0);

      // Bug fix: Create Deepgram listener FIRST (using a dummy placeholder stream),
      // then wait for the WebSocket to open, THEN start the recorder.
      // Previously, the recorder started before Deepgram was ready, dropping the first syllable.

      // We need a broadcast stream. Use a StreamController to bridge recorder → Deepgram.
      final audioController = StreamController<List<int>>.broadcast();

      _liveListener = _deepgram.listen.liveListener(
        audioController.stream,
        queryParams: {
          'model': 'nova-2-general',
          'punctuate': false,
          'interim_results': true,
          'encoding': 'linear16',
          'sample_rate': 16000,
        },
      );

      _deepgramSubscription = _liveListener!.stream.listen(
        (result) {
          if (result.transcript != null && result.transcript!.isNotEmpty) {
            setState(() {
              if (result.isFinal) {
                _fullTranscript +=
                    (_fullTranscript.isEmpty ? '' : ' ') + result.transcript!;
                _currentSegment = '';
              } else {
                _currentSegment = result.transcript!;
              }
            });
            _scrollToBottom();
          }
        },
        onError: (error) {
          debugPrint('Deepgram error: $error');
          audioController.close();
          _stopListening();
        },
      );

      // Start Deepgram WebSocket handshake FIRST
      _liveListener!.start();

      // Wait for WebSocket to fully open before audio starts flowing
      await Future.delayed(const Duration(milliseconds: 400));

      // NOW start the microphone recorder
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      // Pipe recorder audio into both the WAV file and the Deepgram WebSocket
      _audioStreamSubscription = stream.listen((audioData) {
        _audioFileSink?.add(audioData);
        if (!audioController.isClosed) {
          audioController.add(audioData);
        }
      }, onDone: () {
        audioController.close();
      });

    } catch (e) {
      debugPrint('Error starting listener: $e');
      _stopListening();
    }
  }

  Future<void> _stopListening() async {
    if (!_isListening) return;

    if (mounted) {
      setState(() => _isListening = false);
    }

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
        _fullTranscript +=
            (_fullTranscript.isEmpty ? '' : ' ') + _currentSegment;
        _currentSegment = '';
      }

      final finalTranscript = _fullTranscript;

      if (mounted) {
        setState(() {
          // Clear it out for the next recording
          _fullTranscript = '';
        });

        // Auto-send the transcribed text if it's not empty
        if (finalTranscript.trim().isNotEmpty) {
          _sendMessage(finalTranscript);
        }
      }

      if (_currentTurnAudioPath != null && finalTranscript.trim().isNotEmpty) {
        await _finalizeWavFile(_currentTurnAudioPath!);
        // FIRE AND FORGET: Start background fluency analysis for this specific turn
        _processTurnFluency(_currentTurnAudioPath!);
      }
    } catch (e) {
      debugPrint('Error stopping listener: $e');
    }
  }

  void _processTurnFluency(String audioPath) {
    debugPrint("Queuing background fluency analysis for turn...");
    
    final futureObj = FluencyApiService.analyzeAudio(audioPath).then((result) {
      if (mounted) {
        _turnFluencyResults.add(result);
        debugPrint("Successfully captured fluency result for turn.");
      }
    }).catchError((e) {
      debugPrint("Background fluency analysis failed for turn: $e");
      if (mounted) {
        _turnFluencyResults.add({
          "fluency_issues": [],
          "detected_fillers": [],
          "stutters": [],
          "pauses": [],
          "fast_phrases": [],
        });
      }
    });

    _activeFluencyTasks.add(futureObj);
  }

  // --- Audio File Handling ---
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
      debugPrint('Error finalizing WAV file: $e');
    }
  }

  List<int> _getWavHeaderBytes(int dataSize) {
    return [
      0x52,
      0x49,
      0x46,
      0x46,
      ...(_int32ToBytes(dataSize + 36)),
      0x57,
      0x41,
      0x56,
      0x45,
      0x66,
      0x6D,
      0x74,
      0x20,
      0x10,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x01,
      0x00,
      0x80,
      0x3E,
      0x00,
      0x00,
      0x00,
      0x7D,
      0x00,
      0x00,
      0x02,
      0x00,
      0x10,
      0x00,
      0x64,
      0x61,
      0x74,
      0x61,
      ...(_int32ToBytes(dataSize)),
    ];
  }

  void _writeWavHeader(IOSink sink, int dataSize) {
    sink.add(_getWavHeaderBytes(dataSize));
  }

  List<int> _int32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  void _scrollToBottom() {
    // Add a small delay to allow the ListView to build before scrolling
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _endConversation() async {
    if (_isFinished) return;

    setState(() {
      _isFinished = true;
      _isLoading = true; // Show a spinner while we compile the report
    });
    FocusScope.of(context).unfocus();
    _scrollToBottom();

    if (_userTranscripts.isEmpty) {
      setState(() => _isLoading = false);
      return; // Nothing to analyze
    }

    try {
      // 1. GRAMMAR: Batch the entire conversation transcript
      // Join with a period and space so LanguageTool can correctly identify sentence boundaries
      final fullTextToAnalyze = _userTranscripts.join(". ");
      final grammarFuture = GrammarApiService.analyzeText(
        fullTextToAnalyze,
      ).catchError((e) {
        debugPrint("Grammar API Error gracefully caught: $e");
        return GrammarAnalysisResult(
          originalText: fullTextToAnalyze,
          correctedText:
              "Grammar API is currently offline. Please try again later.",
          mistakes: [],
          summary: GrammarSummary(
            totalMistakes: 0,
            wordCount: 0,
            sentenceCount: 0,
            grammarScore: 0,
          ),
          mistakeCategories: {},
          message: e.toString(),
        );
      });

      // 2. FLUENCY: Aggregate the background queue results
      // Await all pending fluency API requests so we don't drop the latest audio turn!
      if (_activeFluencyTasks.isNotEmpty) {
        await Future.wait(_activeFluencyTasks);
      }

      List<dynamic> combinedFluencyIssues = [];
      List<dynamic> combinedFillers = [];
      List<dynamic> combinedStutters = [];
      List<dynamic> combinedPauses = [];
      List<dynamic> combinedFastPhrases = [];
      double totalSpeechRate = 0;
      int turnsWithSpeechRate = 0;
      List<String> combinedAnnotatedTranscripts = [];

      for (var result in _turnFluencyResults) {
        if (result.containsKey('fluency_issues'))
          combinedFluencyIssues.addAll(result['fluency_issues']);
        if (result.containsKey('detected_fillers'))
          combinedFillers.addAll(result['detected_fillers']);
        if (result.containsKey('stutters'))
          combinedStutters.addAll(result['stutters']);
        if (result.containsKey('pauses'))
          combinedPauses.addAll(result['pauses']);
        if (result.containsKey('fast_phrases'))
          combinedFastPhrases.addAll(result['fast_phrases']);

        if (result.containsKey('annotated_transcript')) {
          combinedAnnotatedTranscripts.add(result['annotated_transcript']);
        }

        // The unified report expects a metrics object to calculate the final score
        if (result.containsKey('metrics') &&
            result['metrics'].containsKey('avg_speech_rate')) {
          totalSpeechRate +=
              (result['metrics']['avg_speech_rate'] as num).toDouble();
          turnsWithSpeechRate++;
        }
      }

      double avgSpeechRate =
          turnsWithSpeechRate > 0
              ? (totalSpeechRate / turnsWithSpeechRate)
              : 130.0;

      final combinedFluencyResult = {
        "transcript": fullTextToAnalyze,
        "annotated_transcript": combinedAnnotatedTranscripts.join(" "),
        "fluency_issues": combinedFluencyIssues,
        "detected_fillers": combinedFillers,
        "stutters": combinedStutters,
        "pauses": combinedPauses,
        "fast_phrases": combinedFastPhrases,
        "metrics": {
          "avg_speech_rate": avgSpeechRate,
          // You might need to mock or average other metrics like grammar_errors depending on your UI
        },
      };
      final grammarResult = await grammarFuture;

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => UnifiedReportScreen(
              grammarResult: grammarResult,
              fluencyResult: combinedFluencyResult,
              audioPath: _currentTurnAudioPath, // Pass the last known clip
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error generating unified report: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate report: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _deepgramSubscription?.cancel();
    _liveListener?.close();
    _audioStreamSubscription?.cancel();
    _audioFileSink?.close();
    _controller.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose(); // Dispose the audio player
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleMessages =
        _messages.where((m) => m["isVisible"] == true).toList();

    return Scaffold(
      backgroundColor: softBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              widget.scenario.title,
              style: TextStyle(
                color: textDark,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "AI Assistant",
              style: TextStyle(color: textGrey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          // ACCENT SELECTION DROPDOWN (Improved UI)
          Padding(
            padding: const EdgeInsets.only(right: 8.0, top: 8.0, bottom: 8.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: secondaryPurple.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryPurple.withOpacity(0.5)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedAccent,
                  icon: Icon(Icons.arrow_drop_down, color: primaryPurple, size: 20),
                  dropdownColor: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  alignment: Alignment.center,
                  style: TextStyle(
                    color: primaryPurple, 
                    fontWeight: FontWeight.w600, 
                    fontSize: 13
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'american', 
                      child: Row(
                        children: const [
                          Text("🇺🇸", style: TextStyle(fontSize: 16)),
                          SizedBox(width: 6),
                          Text("US"),
                        ],
                      )
                    ),
                    DropdownMenuItem(
                      value: 'british', 
                      child: Row(
                        children: const [
                          Text("🇬🇧", style: TextStyle(fontSize: 16)),
                          SizedBox(width: 6),
                          Text("UK"),
                        ],
                      )
                    ),
                    DropdownMenuItem(
                      value: 'pakistani', 
                      child: Row(
                        children: const [
                          Text("🇵🇰", style: TextStyle(fontSize: 16)),
                          SizedBox(width: 6),
                          Text("PK"),
                        ],
                      )
                    ),
                  ],
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedAccent = newValue;
                      });
                    }
                  },
                ),
              ),
            ),
          ),
          if (!_isFinished)
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: TextButton(
                onPressed: _endConversation,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text(
                  "End",
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 20,
                      bottom:
                          _isListening ? 220 : 20, // Add space for floating mic
                    ),
                    itemCount:
                        visibleMessages.length +
                        (_isListening &&
                                (_fullTranscript.isNotEmpty ||
                                    _currentSegment.isNotEmpty)
                            ? 1
                            : 0),
                    itemBuilder: (context, index) {
                      if (index < visibleMessages.length) {
                        final msg = visibleMessages[index];
                        final isUser = msg["role"] == "user";
                        final isError = msg["role"] == "system_error";

                        return _buildMessageBubble(
                          text: msg["content"],
                          isUser: isUser,
                          timestamp: msg["timestamp"] as DateTime,
                          isError: isError,
                        );
                      } else {
                        // Build the live transcript bubble
                        final combinedTranscript =
                            _fullTranscript +
                            (_currentSegment.isEmpty
                                ? ''
                                : (_fullTranscript.isEmpty ? '' : ' ') +
                                    _currentSegment);
                        return _buildMessageBubble(
                          text: combinedTranscript,
                          isUser: true,
                          timestamp: DateTime.now(),
                          isError: false,
                          isLive: true,
                        );
                      }
                    },
                  ),
                ),
                if (_isLoading)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 20, bottom: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(primaryPurple),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isFinished ? 'Generating report...' : 'AI Assistant is typing...',
                            style: TextStyle(
                              color: primaryPurple,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                _buildInputArea(),
              ],
            ),

            // Build the floating microphone overlay
            if (_isListening) _buildListeningOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required String text,
    required bool isUser,
    required DateTime timestamp,
    bool isError = false,
    bool isLive = false,
  }) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:
              isError
                  ? Colors.red.shade100
                  : (isUser ? primaryPurple : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser || isError ? 20 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                color:
                    isError
                        ? Colors.red.shade900
                        : (isUser ? Colors.white : textDark),
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isLive
                  ? "Listening..."
                  : "${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}",
              style: TextStyle(
                color: isUser ? Colors.white.withOpacity(0.7) : Colors.grey,
                fontSize: 10,
                fontStyle: isLive ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Floating microphone UI matching the mockup, but without blurred background
  Widget _buildListeningOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 80, // Keep input area accessible
      child: GestureDetector(
        onTap: _toggleRecording, // Tap mic to stop
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing mic circle
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: primaryPurple.withAlpha(
                  (255 * 0.15).toInt(),
                ), // Very subtle outer circle
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: primaryPurple.withAlpha(
                      (255 * 0.6).toInt(),
                    ), // Inner darker circle
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 48),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Listening...",
              style: TextStyle(
                color: primaryPurple,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    if (_isFinished) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          border: Border(top: BorderSide(color: Colors.green.shade200)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              "Conversation Finished",
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Tooltip(
            message: _isTtsPlaying ? 'Wait for AI to finish speaking' : (_isListening ? 'Tap to stop' : 'Tap to speak'),
            child: InkWell(
              onTap: _toggleRecording,
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isTtsPlaying
                      ? Colors.grey.withOpacity(0.15)
                      : (_isListening
                          ? Colors.red.withOpacity(0.2)
                          : secondaryPurple.withOpacity(0.3)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isTtsPlaying
                      ? Icons.volume_up_rounded
                      : (_isListening ? Icons.mic : Icons.mic_rounded),
                  color: _isTtsPlaying
                      ? Colors.grey
                      : (_isListening ? Colors.red : primaryPurple),
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: softBackground,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _controller,
                style: TextStyle(color: textDark),
                decoration: InputDecoration(
                  hintText: 'Write your message or speak',
                  hintStyle: TextStyle(color: textGrey.withOpacity(0.6)),
                  border: InputBorder.none,
                ),
                onSubmitted: _sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: () => _sendMessage(_controller.text),
            child: CircleAvatar(
              backgroundColor: primaryPurple,
              radius: 22,
              child: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
