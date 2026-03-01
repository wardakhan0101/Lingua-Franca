import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:lingua_franca/screens/homophone_corrector.dart';

class NativeSttScreenTest extends StatefulWidget {
  const NativeSttScreenTest({super.key});

  @override
  State<NativeSttScreenTest> createState() => _NativeSttScreenTestState();
}

class _NativeSttScreenTestState extends State<NativeSttScreenTest> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isInitialized = false;
  String _recognizedText = '';
  String _currentText = '';
  double _confidence = 0.0;

  final HomophoneCorrector _corrector = HomophoneCorrector();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initializeSpeech();
  }

  Future<void> _initializeSpeech() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        debugPrint('Speech status: $status');
        if (status == 'done' || status == 'notListening') {
          setState(() {
            _isListening = false;
          });
        }
      },
      onError: (error) {
        debugPrint('Speech error: $error');
        setState(() {
          _isListening = false;
        });
        _showMessage('Error: ${error.errorMsg}');
      },
    );

    setState(() {
      _isInitialized = available;
    });

    if (!available) {
      _showMessage('Speech recognition not available');
    }
  }

  Future<void> _startListening() async {
    if (!_isInitialized) {
      _showMessage('Please wait, initializing...');
      return;
    }

    setState(() {
      _isListening = true;
      _currentText = '';
    });

    await _speech.listen(
      onResult: (result) {
        setState(() {
          // Get raw text
          String rawText = result.recognizedWords;

          // Apply homophone correction
          String correctedText = _corrector.correctText(rawText);

          // Apply basic enhancements (capitalization, etc.)
          correctedText = _corrector.enhanceText(correctedText);

          _currentText = correctedText;
          _confidence = result.confidence;

          if (result.finalResult) {
            if (_recognizedText.isNotEmpty) {
              _recognizedText += ' ';
            }
            _recognizedText += correctedText;
            _currentText = '';
          }
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      listenMode: stt.ListenMode.confirmation,
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
      if (_currentText.isNotEmpty) {
        if (_recognizedText.isNotEmpty) {
          _recognizedText += ' ';
        }
        _recognizedText += _currentText;
        _currentText = '';
      }
    });
  }

  void _clearText() {
    setState(() {
      _recognizedText = '';
      _currentText = '';
      _confidence = 0.0;
    });
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF7BB9E8),
              Color(0xFF9B7EC9),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Text(
                      'Native STT',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      // Status
                      Text(
                        _isListening
                            ? 'Listening...'
                            : _isInitialized
                            ? 'Tap mic to start'
                            : 'Initializing...',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Text Display Box
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_recognizedText.isEmpty && _currentText.isEmpty)
                                  const Center(
                                    child: Text(
                                      'Your speech will appear here...',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  )
                                else
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (_recognizedText.isNotEmpty)
                                        Text(
                                          _recognizedText,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            color: Colors.black87,
                                            height: 1.5,
                                          ),
                                        ),
                                      if (_currentText.isNotEmpty)
                                        Text(
                                          _currentText,
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: Colors.blue.shade700,
                                            height: 1.5,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Confidence
                      if (_confidence > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Confidence: ${(_confidence * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),

                      // ADD THIS (optional - shows corrections are active)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.auto_fix_high, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'Auto-correction enabled',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Mic Button
                      GestureDetector(
                        onTap: _isListening ? _stopListening : _startListening,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isListening
                                ? Colors.red.shade400
                                : Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: _isListening
                                    ? Colors.red.withOpacity(0.4)
                                    : Colors.black.withOpacity(0.2),
                                blurRadius: 20,
                                spreadRadius: _isListening ? 5 : 0,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isListening ? Icons.mic : Icons.mic_none,
                            size: 50,
                            color: _isListening
                                ? Colors.white
                                : const Color(0xFF6B72AB),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Helper Text
                      Text(
                        _isListening
                            ? 'Tap to stop'
                            : 'Tap to record',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Clear Button
                      if (_recognizedText.isNotEmpty || _currentText.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _clearText,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF6B72AB),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.clear),
                            label: const Text(
                              'Clear Text',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }
}