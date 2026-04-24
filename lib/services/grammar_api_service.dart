import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GrammarApiService {
  // 🌐 Your deployed Cloud Run API
  static const String baseUrl =
      'https://grammar-checker-702584631438.us-central1.run.app';

  /// Analyze text for grammar mistakes. Pass [requiredTense] (e.g.
  /// 'past_simple', 'past_perfect', 'present_perfect', 'future_simple') to
  /// additionally get a `tense_compliance` verdict in the response summary.
  /// Used by the assessment module to grade tense-specific grammar questions.
  static Future<GrammarAnalysisResult> analyzeText(
    String text, {
    String? requiredTense,
  }) async {
    try {
      debugPrint('==== GRAMMAR API REQUEST ====');
      debugPrint('Payload text: "$text"');
      if (requiredTense != null) {
        debugPrint('Required tense: $requiredTense');
      }

      final url = Uri.parse('$baseUrl/analyze');

      final body = <String, dynamic>{'text': text};
      if (requiredTense != null) {
        body['required_tense'] = requiredTense;
      }

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 90), onTimeout: () {
        throw Exception('Grammar API timed out after 90 seconds (Cloud Run cold start?)');
      });

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

  // Round-trips through Firestore: keys match the API shape so the same
  // fromJson factory can rebuild the object when we re-open a past report.
  Map<String, dynamic> toJson() => {
        'original_text': originalText,
        'corrected_text': correctedText,
        'message': message,
        'mistakes': mistakes.map((m) => m.toJson()).toList(),
        'summary': summary.toJson(),
        'mistake_categories': mistakeCategories,
      };
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

  Map<String, dynamic> toJson() => {
        'error_type': errorType,
        'rule_id': ruleId,
        'message': message,
        'mistake_text': mistakeText,
        'context': context,
        'position': position,
        'suggestions': suggestions,
        'severity': severity,
      };
}

class GrammarSummary {
  final int totalMistakes;
  final int wordCount;
  final int sentenceCount;
  final double grammarScore;
  final TenseCompliance? tenseCompliance;
  final String? requiredTense;

  GrammarSummary({
    required this.totalMistakes,
    required this.wordCount,
    required this.sentenceCount,
    required this.grammarScore,
    this.tenseCompliance,
    this.requiredTense,
  });

  factory GrammarSummary.fromJson(Map<String, dynamic> json) {
    return GrammarSummary(
      totalMistakes: json['total_rule_based_mistakes'] ?? 0,
      wordCount: json['word_count'] ?? 0,
      sentenceCount: json['sentence_count'] ?? 0,
      grammarScore: (json['grammar_score'] ?? 0).toDouble(),
      tenseCompliance: json['tense_compliance'] != null
          ? TenseCompliance.fromJson(json['tense_compliance'])
          : null,
      requiredTense: json['required_tense'],
    );
  }

  Map<String, dynamic> toJson() => {
        'total_rule_based_mistakes': totalMistakes,
        'word_count': wordCount,
        'sentence_count': sentenceCount,
        'grammar_score': grammarScore,
        if (tenseCompliance != null) 'tense_compliance': tenseCompliance!.toJson(),
        if (requiredTense != null) 'required_tense': requiredTense,
      };
}

/// Returned inside GrammarSummary only when analyzeText() was called with a
/// requiredTense. Captures how many of the user's verb events matched the
/// requested tense.
class TenseCompliance {
  final int compliantCount;
  final int totalVerbs;
  final double percent; // 0.0 – 1.0
  final bool compliant; // true when percent >= 0.75

  TenseCompliance({
    required this.compliantCount,
    required this.totalVerbs,
    required this.percent,
    required this.compliant,
  });

  factory TenseCompliance.fromJson(Map<String, dynamic> json) {
    return TenseCompliance(
      compliantCount: json['compliant_count'] ?? 0,
      totalVerbs: json['total_verbs'] ?? 0,
      percent: (json['percent'] ?? 0).toDouble(),
      compliant: json['compliant'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'compliant_count': compliantCount,
        'total_verbs': totalVerbs,
        'percent': percent,
        'compliant': compliant,
      };
}
