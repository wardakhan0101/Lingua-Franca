import 'dart:typed_data';
import 'package:http/http.dart' as http;

class TtsApiService {
  // adb reverse tcp:8000 tcp:8000 allows 127.0.0.1 to work via USB cable
  static const String _baseUrl = 'http://127.0.0.1:8000';

  /// Sends text + accent to FastAPI, returns raw audio bytes (WAV)
  static Future<Uint8List> synthesize({
    required String text,
    required String accent,
  }) async {
    print('[TTS] Sending request to $_baseUrl/synthesize');
    print('[TTS] Text: $text');
    print('[TTS] Accent: $accent');

    try {
      print('[TTS] Making HTTP POST...');
      final response = await http.post(
        Uri.parse('$_baseUrl/synthesize'),
        headers: {'Content-Type': 'application/json'},
        body: '{"text": ${_escapeJson(text)}, "accent": "$accent"}',
      ).timeout(const Duration(seconds: 15));

      print('[TTS] Response status: ${response.statusCode}');
      print('[TTS] Response size: ${response.bodyBytes.length} bytes');

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print('[TTS] Error body: ${response.body}');
        throw Exception('TTS server error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('[TTS] Exception caught: $e');
      throw Exception('Failed to reach TTS server. Is FastAPI running? ($e)');
    }
  }

  static String _escapeJson(String text) {
    final escaped = text
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
    return '"$escaped"';
  }
}