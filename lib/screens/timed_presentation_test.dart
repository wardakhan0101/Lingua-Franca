import 'dart:async';
import 'dart:io'; // Needed for File operations
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart'; // Needed to save file
import 'package:record/record.dart'; // Needed for audio recording
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'homophone_corrector.dart';
import 'fluency_screen.dart'; // Import your report screen

class PresentationPracticeScreen extends StatefulWidget {
  const PresentationPracticeScreen({super.key});

  @override
  State<PresentationPracticeScreen> createState() => _PresentationPracticeScreenState();
}

class _PresentationPracticeScreenState extends State<PresentationPracticeScreen> {
  // Timer Variables
  Timer? _timer;
  int _totalSeconds = 30;
  int _remainingSeconds = 30;
  bool _isRecording = false;
  String _currentTopic = "";

  // Audio Recorder Variables (NEW)
  late AudioRecorder _audioRecorder;
  String? _recordedFilePath;

  // Speech-to-Text Variables
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isInitialized = false;
  String _recognizedText = '';
  String _currentText = '';
  double _confidence = 0.0;
  final HomophoneCorrector _corrector = HomophoneCorrector();

  final List<String> _topics = [
    "Describe the benefits of remote work",
    "Explain the importance of time management",
    "Discuss the future of Artificial Intelligence",
    "How to maintain a healthy work-life balance",
    "The impact of social media on youth"
  ];

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder(); // Initialize Recorder
    _pickRandomTopic();
    _initializeSpeech();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _speech.stop();
    _audioRecorder.dispose(); // Dispose Recorder
    super.dispose();
  }

  Future<void> _finishAndNavigate() async {
    // 1. Stop Timer
    _timer?.cancel();

    // 2. Stop STT
    await _speech.stop();

    // 3. Stop Audio Recorder & Get Path
    String? path; // This is nullable
    if (await _audioRecorder.isRecording()) {
      path = await _audioRecorder.stop();
    }

    setState(() {
      _isRecording = false;
      _isListening = false;
      if (_currentText.isNotEmpty) {
        _recognizedText += (_recognizedText.isEmpty ? '' : ' ') + _currentText;
        _currentText = '';
      }
    });

    // 4. Navigate to Fluency Report (Fixed Logic)
    if (path != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FluencyScreen(audioPath: path!), // Added '!' here
        ),
      );
    } else {
      // Optional: Handle the case where recording failed
      debugPrint("Error: Recording path was null");
    }
  }

  // --- Timer Methods ---

  void _pickRandomTopic() {
    setState(() {
      _currentTopic = _topics[Random().nextInt(_topics.length)];
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        // Timer reached 0 -> Finish Session
        _finishAndNavigate();
      }
    });
  }

  // --- Speech-to-Text & Recording Methods ---

  Future<void> _initializeSpeech() async {
    _speech = stt.SpeechToText();
    bool available = await _speech.initialize(
      onStatus: (status) {
        // Handled manually in _finishAndNavigate to prevent UI flickering
      },
      onError: (error) => debugPrint('Speech error: $error'),
    );
    setState(() => _isInitialized = available);
  }

  Future<void> _startSession() async {
    if (!_isInitialized) return;

    // 1. Setup Audio File Path
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/practice_${DateTime.now().millisecondsSinceEpoch}.wav';

    // 2. Start Audio Recorder
    // Check permission first (omitted for brevity, assume granted or handled in main)
    await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: filePath
    );

    // 3. Start Timer
    setState(() {
      _isRecording = true;
      _isListening = true;
      _currentText = '';
      _remainingSeconds = _totalSeconds; // Reset timer
    });
    _startTimer();

    // 4. Start Speech to Text (Visual only)
    await _speech.listen(
      onResult: (result) {
        setState(() {
          String rawText = result.recognizedWords;
          String correctedText = _corrector.correctText(rawText);
          _currentText = _corrector.enhanceText(correctedText);
          _confidence = result.confidence;

          if (result.finalResult) {
            _recognizedText += (_recognizedText.isEmpty ? '' : ' ') + _currentText;
            _currentText = '';
            // Restart listening if still recording
            if (_isRecording && mounted) {
              _speech.listen(
                onResult: (r) { /* Logic repeated for simplicity or extract to method */ },
              );
            }
          }
        });
      },
      listenFor: const Duration(seconds: 30),
      partialResults: true,
      listenMode: stt.ListenMode.dictation,
    );
  }

  void _toggleSession() {
    if (_isRecording) {
      _finishAndNavigate(); // User tapped stop manually
    } else {
      _startSession(); // User tapped start
    }
  }

  void _clearText() {
    setState(() {
      _recognizedText = '';
      _currentText = '';
      _confidence = 0.0;
    });
  }

  // --- UI Build ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Presentation Practice", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          children: [
            // Topic Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)),
              child: Text("Topic: $_currentTopic", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 30),

            // Timer
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 180, height: 180,
                  child: CircularProgressIndicator(
                    value: _remainingSeconds / _totalSeconds,
                    strokeWidth: 10,
                    color: Colors.deepPurple,
                    backgroundColor: Colors.grey[200],
                  ),
                ),
                Text("$_remainingSeconds", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              ],
            ),
            const SizedBox(height: 20),

            // Mic Button (Main Control)
            GestureDetector(
              onTap: _toggleSession,
              child: Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red : Colors.deepOrange,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 35),
              ),
            ),
            const SizedBox(height: 10),
            Text(_isRecording ? "Tap to Finish Early" : "Tap to Start", style: const TextStyle(color: Colors.grey)),

            const SizedBox(height: 20),

            // Transcription Display
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _recognizedText + (_currentText.isNotEmpty ? " $_currentText" : ""),
                    style: const TextStyle(fontSize: 15, height: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Keep your AudioWaveVisualizer class as is...
class AudioWaveVisualizer extends StatefulWidget {
  const AudioWaveVisualizer({super.key});
  @override
  State<AudioWaveVisualizer> createState() => _AudioWaveVisualizerState();
}

class _AudioWaveVisualizerState extends State<AudioWaveVisualizer> {
  // ... (Your existing visualizer code) ...
  @override
  Widget build(BuildContext context) { return Container(); } // Placeholder for brevity
}