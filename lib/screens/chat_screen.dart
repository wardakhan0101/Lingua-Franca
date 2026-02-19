import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'timed_presentation_test.dart';
import 'homophone_corrector.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;

  // STT variables
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _isInitialized = false;
  String _currentTranscription = '';

  final HomophoneCorrector _corrector = HomophoneCorrector();

  // Colors
  final Color primaryPurple = const Color(0xFF8A48F0);
  final Color secondaryPurple = const Color(0xFFD9BFFF);
  final Color softBackground = const Color(0xFFF7F7FA);
  final Color textDark = const Color(0xFF101828);
  final Color textGrey = const Color(0xFF667085);

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initializeSpeech();
    _initializeChat();
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

  void _initializeChat() {
    final apiKey = dotenv.env['GROQ_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(
          text: "Hello! 👋 I'm your language learning companion. What language would you like to practice today?",
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    });
  }

  // Start recording
  Future<void> _toggleRecording() async {
    if (_isListening) {
      // If already listening, stop it
      await _stopListening();
    } else {
      // Start fresh recording
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_isInitialized) {
      _showMessage('Please wait, initializing...');
      return;
    }

    setState(() {
      _isListening = true;
      _currentTranscription = '';
      _controller.clear();
    });

    await _speech.listen(
      onResult: (result) {
        setState(() {
          String rawText = result.recognizedWords;

          // Apply homophone correction
          String correctedText = _corrector.correctText(rawText);
          correctedText = _corrector.enhanceText(correctedText);

          // Always update the current transcription
          _currentTranscription = correctedText;
          _controller.text = correctedText;

          // Move cursor to end
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
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

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    final userMessage = text.trim();

    setState(() {
      _messages.add(ChatMessage(text: userMessage, isUser: true, timestamp: DateTime.now()));
      _isLoading = true;
    });

    _controller.clear();
    _scrollToBottom();

    try {
      final botResponse = await _getGroqResponse();
      setState(() {
        _messages.add(ChatMessage(text: botResponse, isUser: false, timestamp: DateTime.now()));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(text: "Error: ${e.toString()}", isUser: false, timestamp: DateTime.now(), isError: true));
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<String> _getGroqResponse() async {
    final apiKey = dotenv.env['GROQ_API_KEY'];
    const url = 'https://api.groq.com/openai/v1/chat/completions';

    List<Map<String, String>> apiMessages = [
      {"role": "system", "content": "You are a friendly language learning tutor. Keep responses concise (2-4 sentences)."}
    ];

    for (var msg in _messages) {
      apiMessages.add({
        "role": msg.isUser ? "user" : "assistant",
        "content": msg.text,
      });
    }

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "model": "llama-3.1-8b-instant",
          "messages": apiMessages,
          "temperature": 0.7,
          "max_tokens": 1024,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        throw Exception(jsonDecode(response.body)['error']['message']);
      }
    } catch (e) {
      throw Exception("Network Error: $e");
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  // --- UI BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: softBackground,
      appBar: AppBar(
        backgroundColor: softBackground,
        elevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: CircleAvatar(
            backgroundColor: Colors.white,
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: textDark, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: Text(
          'AI Tutor',
          style: TextStyle(color: textDark, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildModeSelector(),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return MessageBubble(
                    message: _messages[index],
                    primaryColor: primaryPurple,
                    secondaryColor: secondaryPurple,
                    textDark: textDark,
                  );
                },
              ),
            ),
            if (_isLoading)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 10),
                  child: Text(
                    'AI is thinking...',
                    style: TextStyle(color: textGrey, fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
              ),
            // Show listening indicator
            if (_isListening)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mic,
                        color: Colors.red,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Listening...',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            _buildSmartInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: primaryPurple,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Center(
                  child: Text(
                    "Freestyle",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const PresentationPracticeScreen(),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Center(
                    child: Text(
                      "Timed Presentation",
                      style: TextStyle(color: textGrey, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Row(
        children: [
          // Mic button with recording state
          InkWell(
            onTap: _toggleRecording,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isListening
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
                border: _isListening
                    ? Border.all(color: Colors.red.withOpacity(0.3), width: 2)
                    : null,
              ),
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: _isListening ? 'Listening...' : 'Type something...',
                  hintStyle: TextStyle(
                    color: _isListening
                        ? Colors.red.withOpacity(0.6)
                        : textGrey.withOpacity(0.6),
                  ),
                  border: InputBorder.none,
                ),
                onSubmitted: _sendMessage,
                readOnly: _isListening, // Make readonly while listening
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Send button - always works
          InkWell(
            onTap: () => _sendMessage(_controller.text),
            child: CircleAvatar(
              backgroundColor: primaryPurple,
              radius: 22,
              child: const Icon(
                Icons.arrow_upward_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Data Models
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;
  ChatMessage({required this.text, required this.isUser, required this.timestamp, this.isError = false});
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Color primaryColor;
  final Color secondaryColor;
  final Color textDark;

  const MessageBubble({
    super.key,
    required this.message,
    required this.primaryColor,
    required this.secondaryColor,
    required this.textDark,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? primaryColor : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 20),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text, style: TextStyle(color: isUser ? Colors.white : textDark, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              "${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}",
              style: TextStyle(color: isUser ? Colors.white.withOpacity(0.7) : Colors.grey, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}