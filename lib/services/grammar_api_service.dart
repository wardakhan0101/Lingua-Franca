import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GrammarApiService {
  // 🌐 Your deployed Cloud Run API
  static const String baseUrl =
      'https://grammar-checker-702584631438.us-central1.run.app';

  /// Analyze text for grammar mistakes
  static Future<GrammarAnalysisResult> analyzeText(String text) async {
    try {
      debugPrint('==== GRAMMAR API REQUEST ====');
      debugPrint('Payload text: "$text"');

      final url = Uri.parse('$baseUrl/analyze');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        debugPrint('==== GRAMMAR API RESPONSE ====');
        debugPrint(response.body);
        final data = jsonDecode(response.body);
        return GrammarAnalysisResult.fromJson(data);
      } else {
        debugPrint('==== GRAMMAR API ERROR ====');
        debugPrint(response.statusCode.toString());
        throw Exception('Failed to analyze text: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to grammar API: $e');
    }
  }
}

// 📊 Models for API Response

class GrammarAnalysisResult {
  final String originalText;
  final String correctedText;
  final List<GrammarMistake> mistakes;
  final GrammarSummary summary;
  final Map<String, int> mistakeCategories;
  final String message;

  GrammarAnalysisResult({
    required this.originalText,
    required this.correctedText,
    required this.mistakes,
    required this.summary,
    required this.mistakeCategories,
    required this.message,
  });

  factory GrammarAnalysisResult.fromJson(Map<String, dynamic> json) {
    return GrammarAnalysisResult(
      originalText: json['original_text'] ?? '',
      correctedText: json['corrected_text'] ?? '',
      mistakes:
          (json['mistakes'] as List?)
              ?.map((m) => GrammarMistake.fromJson(m))
              .toList() ??
          [],
      summary: GrammarSummary.fromJson(json['summary'] ?? {}),
      mistakeCategories: Map<String, int>.from(
        json['mistake_categories'] ?? {},
      ),
      message: json['message'] ?? '',
    );
  }
}

class GrammarMistake {
  final String errorType;
  final String ruleId;
  final String message;
  final String mistakeText;
  final String context;
  final Map<String, dynamic> position;
  final List<String> suggestions;
  final String severity;

  GrammarMistake({
    required this.errorType,
    required this.ruleId,
    required this.message,
    required this.mistakeText,
    required this.context,
    required this.position,
    required this.suggestions,
    required this.severity,
  });

  factory GrammarMistake.fromJson(Map<String, dynamic> json) {
    return GrammarMistake(
      errorType: json['error_type'] ?? '',
      ruleId: json['rule_id'] ?? '',
      message: json['message'] ?? '',
      mistakeText: json['mistake_text'] ?? '',
      context: json['context'] ?? '',
      position: json['position'] ?? {},
      suggestions: List<String>.from(json['suggestions'] ?? []),
      severity: json['severity'] ?? 'medium',
    );
  }
}

class GrammarSummary {
  final int totalMistakes;
  final int wordCount;
  final int sentenceCount;
  final double grammarScore;

  GrammarSummary({
    required this.totalMistakes,
    required this.wordCount,
    required this.sentenceCount,
    required this.grammarScore,
  });

  factory GrammarSummary.fromJson(Map<String, dynamic> json) {
    return GrammarSummary(
      totalMistakes: json['total_rule_based_mistakes'] ?? 0,
      wordCount: json['word_count'] ?? 0,
      sentenceCount: json['sentence_count'] ?? 0,
      grammarScore: (json['grammar_score'] ?? 0).toDouble(),
    );
  }
}
