import 'package:flutter/material.dart';
import '../services/stt_service.dart';
import '../services/audio_recorder_service.dart';
import 'dart:async';

class SherpaSttTest extends StatefulWidget {
  const SherpaSttTest({Key? key}) : super(key: key);

  @override
  State<SherpaSttTest> createState() => _SherpaSttTestState();
}

class _SherpaSttTestState extends State<SherpaSttTest> {
  final STTServiceMinimal _sttService = STTServiceMinimal();
  final AudioRecorderService _audioService = AudioRecorderService();

  bool _isInitialized = false;
  bool _isRecording = false;
  String _transcription = '';

  StreamSubscription<List<double>>? _audioSubscription;
  StreamSubscription<String>? _transcriptionSubscription;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    print('🔧 Initializing services...');

    // Initialize audio recorder FIRST (required for flutter_sound)
    try {
      await _audioService.initialize();
      print('✅ Audio service initialized');
    } catch (e) {
      print('❌ Failed to initialize audio service: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize audio: $e')),
        );
      }
      return;
    }

    // Initialize STT service
    final initialized = await _sttService.initialize();
    setState(() {
      _isInitialized = initialized;
    });

    if (!initialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to initialize STT service')),
        );
      }
      return;
    }

    // Listen to transcription updates
    _transcriptionSubscription = _sttService.transcriptionStream.listen((text) {
      print('📱 UI received transcription: $text');
      if (mounted) {
        setState(() {
          _transcription = text;
        });
      }
    });

    // Listen to audio stream and process
    _audioSubscription = _audioService.audioStream.listen((samples) {
      if (_isRecording) {
        print('🔊 Received ${samples.length} audio samples');
        _sttService.processAudio(samples);
      }
    });

    print('✅ Services initialized successfully');
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      print('⏹️ Stopping recording...');

      // Stop audio recording first
      await _audioService.stopRecording();

      // Get final result BEFORE stopping recognition (which releases the stream)
      final finalText = _sttService.getFinalResult();
      print('✅ Final transcription: $finalText');

      // NOW stop recognition (releases the stream)
      _sttService.stopRecognition();

      if (mounted) {
        setState(() {
          _transcription = finalText.isNotEmpty ? finalText : _transcription;
          _isRecording = false;
        });
      }
    } else {
      print('▶️ Starting recording...');

      // Clear previous transcription
      setState(() {
        _transcription = '';
      });

      _sttService.startRecognition();
      final started = await _audioService.startRecording();

      if (started) {
        if (mounted) {
          setState(() {
            _isRecording = true;
          });
        }
        print('✅ Recording started, speak now!');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to start recording')),
          );
        }
        print('❌ Failed to start recording');
      }
    }
  }

  @override
  void dispose() {
    print('🗑️ Disposing speech recognition screen...');
    _audioSubscription?.cancel();
    _transcriptionSubscription?.cancel();
    _sttService.dispose();
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speech Recognition'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status indicator
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isInitialized
                    ? Colors.green.withOpacity(0.2)
                    : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isInitialized ? Icons.check_circle : Icons.hourglass_empty,
                    color: _isInitialized ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isInitialized ? 'Ready to Listen' : 'Initializing...',
                    style: TextStyle(
                      color: _isInitialized ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Transcription display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isRecording ? Colors.red : Colors.grey[400]!,
                  width: _isRecording ? 2 : 1,
                ),
              ),
              constraints: const BoxConstraints(minHeight: 150),
              child: SingleChildScrollView(
                child: Text(
                  _transcription.isEmpty
                      ? (_isRecording
                      ? 'Listening... Speak now!'
                      : 'Tap the microphone to start speaking...')
                      : _transcription,
                  style: TextStyle(
                    fontSize: 18,
                    color: _transcription.isEmpty ? Colors.grey[600] : Colors.black,
                    fontWeight: _transcription.isEmpty ? FontWeight.normal : FontWeight.w500,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 48),

            // Recording button
            GestureDetector(
              onTap: _isInitialized ? _toggleRecording : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isRecording ? 90 : 80,
                height: _isRecording ? 90 : 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording
                      ? Colors.red
                      : (_isInitialized ? Colors.blue : Colors.grey),
                  boxShadow: [
                    BoxShadow(
                      color: (_isRecording ? Colors.red : Colors.blue)
                          .withOpacity(0.4),
                      blurRadius: _isRecording ? 15 : 10,
                      spreadRadius: _isRecording ? 4 : 2,
                    ),
                  ],
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: _isRecording ? 45 : 40,
                ),
              ),
            ),

            const SizedBox(height: 16),

            Text(
              _isRecording
                  ? '🔴 Recording... Tap to stop'
                  : (_isInitialized
                  ? '🎤 Tap to speak'
                  : 'Please wait...'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            if (_isRecording)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Speak clearly in English',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}