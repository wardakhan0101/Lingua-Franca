import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OllamaApiService {
  // Use .env to set IP, otherwise default to 127.0.0.1
  // For physical Android, adb reverse tcp:11434 tcp:11434 makes 127.0.0.1 work natively.
  // For Emulator, you might set OLLAMA_URL=http://10.0.2.2:11434/api/chat in .env
  static String get _baseUrl {
    String? envUrl = dotenv.env['OLLAMA_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      return envUrl;
    }
    return 'http://127.0.0.1:11434/api/chat';
  }
  
  static const String _model = 'llama3.2';

  static Future<String> getResponse(List<Map<String, String>> messages) async {
    if (kDebugMode) print('Ollama API Attempting to connect to: $_baseUrl using $_model');
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': _model,
          'messages': messages,
          'stream': false,
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['message']['content'];
      } else {
        if (kDebugMode) {
          print('Ollama API Error Status: ${response.statusCode}');
          print('Ollama API Error Body: ${response.body}');
        }
        throw Exception('Failed to connect to Local AI. Status: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('Ollama API Exception: $e');
      throw Exception('Network Error: Please ensure Ollama is running locally. ($e)');
    }
  }
}
