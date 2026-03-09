import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:deepgram_speech_to_text/deepgram_speech_to_text.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/scenario.dart';
import '../services/ollama_api_service.dart';

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
  }

  void _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    if (_isListening) {
      await _stopListening();
    }

    final userMessage = text.trim();
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
        }
        _isLoading = false;
        if (isFinished) {
          _isFinished = true;
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

  Future<bool> _checkPermission() async {
    PermissionStatus status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _toggleRecording() async {
    if (_isListening) {
      await _stopListening();
    } else {
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
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      final broadcastStream = stream.asBroadcastStream();

      _liveListener = _deepgram.listen.liveListener(
        broadcastStream,
        queryParams: {
          'model': 'nova-2-general',
          'punctuate': true,
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
              // Removed injecting transcript into the text controller.
              // It will be handled in the UI as a floating bubble or overlay.
            });
            // Ensure we scroll to the bottom after the UI updates with the new transcript text
            _scrollToBottom();
          }
        },
        onError: (error) {
          debugPrint('Deepgram error: $error');
          _stopListening();
        },
      );

      _liveListener!.start();

      // IMPORTANT: Give the Deepgram WebSocket 300ms to fully open and connect
      // *before* we start speaking, otherwise the first word might get sent into the void.
      await Future.delayed(const Duration(milliseconds: 300));
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
    } catch (e) {
      debugPrint('Error stopping listener: $e');
    }
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

  void _endConversation() {
    setState(() {
      _isFinished = true;
    });
    FocusScope.of(context).unfocus();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _recorder.dispose();
    _deepgramSubscription?.cancel();
    _liveListener?.close();
    _controller.dispose();
    _scrollController.dispose();
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
          if (!_isFinished)
            TextButton(
              onPressed: _endConversation,
              child: const Text(
                "End Session",
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
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
                            'AI Assistant is typing...',
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
          InkWell(
            onTap: _toggleRecording,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    _isListening
                        ? Colors.red.withOpacity(0.2)
                        : secondaryPurple.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_rounded,
                color: _isListening ? Colors.red : primaryPurple,
                size: 24,
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
