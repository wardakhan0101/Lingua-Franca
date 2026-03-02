import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class FluencyApiService {
  static Future<Map<String, dynamic>> analyzeAudio(String audioPath) async {
    debugPrint("=== STARTING FLUENCY ANALYSIS ===");

    final apiUrl = dotenv.env['FLUENCY_API_URL'];
    if (apiUrl == null || apiUrl.isEmpty) {
      throw Exception("Error: FLUENCY_API_URL is not set in .env");
    }

    final url = Uri.parse('$apiUrl/analyze');

    final audioFile = File(audioPath);
    final exists = await audioFile.exists();
    debugPrint("File exists: $exists");

    if (!exists) {
      throw Exception("Audio file not found at: $audioPath");
    }

    final audioBytes = await audioFile.readAsBytes();
    debugPrint("Audio file size: ${audioBytes.length} bytes");

    if (audioBytes.length <= 44) {
      throw Exception("Audio file is empty or invalid (only ${audioBytes.length} bytes)");
    }

    // Send as multipart/form-data to our Python API
    debugPrint("Sending request to Fluency Engine API...");
    final request = http.MultipartRequest('POST', url);
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      audioBytes,
      filename: 'recording.wav',
      contentType: MediaType('audio', 'wav'),
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    debugPrint("Fluency API response status: ${response.statusCode}");

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      debugPrint("Fluency API response received");
      return data;
    } else {
      debugPrint("Fluency API error: ${response.body}");
      throw Exception('Failed to analyze audio: ${response.statusCode} - ${response.body}');
    }
  }
}
