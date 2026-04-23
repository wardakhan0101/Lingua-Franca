import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class PronunciationApiService {
  static Future<Map<String, dynamic>> analyzePronunciation({
    required String audioPath,
    required String transcript,
    required List<Map<String, dynamic>> whisperWords,
  }) async {
    debugPrint("=== STARTING PRONUNCIATION ANALYSIS ===");

    final apiUrl = dotenv.env['PRONUNCIATION_API_URL'];
    if (apiUrl == null || apiUrl.isEmpty) {
      throw Exception("Error: PRONUNCIATION_API_URL is not set in .env");
    }

    final url = Uri.parse('$apiUrl/analyze');

    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      throw Exception("Audio file not found at: $audioPath");
    }

    final audioBytes = await audioFile.readAsBytes();
    if (audioBytes.length <= 44) {
      throw Exception(
        "Audio file is empty or invalid (${audioBytes.length} bytes)",
      );
    }

    if (whisperWords.isEmpty) {
      throw Exception(
        "whisperWords is empty — pronunciation engine needs word timings",
      );
    }

    debugPrint(
      "Pronunciation: sending ${audioBytes.length} bytes, "
      "${whisperWords.length} words",
    );

    final request =
        http.MultipartRequest('POST', url)
          ..fields['transcript'] = transcript
          ..fields['whisper_words'] = jsonEncode(whisperWords)
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              audioBytes,
              filename: 'recording.wav',
              contentType: MediaType('audio', 'wav'),
            ),
          );

    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint(
        "Pronunciation result: overall=${data['overall_score']}, "
        "${(data['per_word'] as List?)?.length ?? 0} words",
      );
      return data;
    } else {
      debugPrint("Pronunciation API error: ${response.body}");
      throw Exception(
        'Pronunciation API failed: ${response.statusCode} - ${response.body}',
      );
    }
  }

  // Merge per-turn pronunciation responses from scenario chat into a single
  // session-level aggregate matching the engine's response shape. Word order
  // is preserved, phoneme stats are summed.
  static Map<String, dynamic> mergeTurnResults(
    List<Map<String, dynamic>> turnResults,
  ) {
    if (turnResults.isEmpty) {
      return {'overall_score': 0, 'per_word': [], 'phoneme_stats': {}};
    }

    final List<dynamic> perWord = [];
    final Map<String, Map<String, dynamic>> phonemeStats = {};
    final List<int> wordScores = [];

    for (final turn in turnResults) {
      final words = turn['per_word'] as List? ?? const [];
      for (final w in words) {
        perWord.add(w);
        final score = w['score'];
        if (score is int) wordScores.add(score);
      }

      final stats = turn['phoneme_stats'] as Map? ?? const {};
      stats.forEach((phoneme, raw) {
        final v = Map<String, dynamic>.from(raw as Map);
        final existing =
            phonemeStats[phoneme] ??
            {'expected': 0, 'correct': 0, 'substitutions': <String, int>{}};
        existing['expected'] =
            (existing['expected'] as int) + ((v['expected'] as int?) ?? 0);
        existing['correct'] =
            (existing['correct'] as int) + ((v['correct'] as int?) ?? 0);
        final subsRaw = v['substitutions'];
        if (subsRaw is Map) {
          final subs = existing['substitutions'] as Map<String, int>;
          subsRaw.forEach((k, val) {
            final key = k.toString();
            subs[key] = (subs[key] ?? 0) + ((val as num?)?.toInt() ?? 0);
          });
        }
        phonemeStats[phoneme as String] = existing;
      });
    }

    final overall =
        wordScores.isEmpty
            ? 0
            : (wordScores.reduce((a, b) => a + b) / wordScores.length).round();

    return {
      'overall_score': overall,
      'per_word': perWord,
      'phoneme_stats': phonemeStats,
    };
  }
}
