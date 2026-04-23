import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AnalysisStorageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Store fluency analysis result
  Future<void> storeFluencyAnalysis({
    required String transcript,
    required List<Map<String, dynamic>> fluencyIssues,
    required String audioPath,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final analysisData = {
        'userId': userId,
        'type': 'fluency',
        'timestamp': FieldValue.serverTimestamp(),
        'transcript': transcript,
        'fluencyIssues': fluencyIssues,
        'audioPath': audioPath,
        'issueCount': fluencyIssues.length,
      };

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('analyses')
          .add(analysisData);

      print('✓ Fluency analysis stored successfully');
    } catch (e) {
      print('Error storing fluency analysis: $e');
      rethrow;
    }
  }

  // Store grammar analysis result
  Future<void> storeGrammarAnalysis({
    required String originalText,
    required String correctedText,
    required String message,
    required List<Map<String, dynamic>> mistakes,
    required Map<String, int> mistakeCategories,
    required int totalMistakes,
    required int wordCount,
    required int sentenceCount,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final analysisData = {
        'userId': userId,
        'type': 'grammar',
        'timestamp': FieldValue.serverTimestamp(),
        'originalText': originalText,
        'correctedText': correctedText,
        'message': message,
        'mistakes': mistakes,
        'mistakeCategories': mistakeCategories,
        'summary': {
          'totalMistakes': totalMistakes,
          'wordCount': wordCount,
          'sentenceCount': sentenceCount,
        },
      };

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('analyses')
          .add(analysisData);

      print('✓ Grammar analysis stored successfully');
    } catch (e) {
      print('Error storing grammar analysis: $e');
      rethrow;
    }
  }

  // Store pronunciation analysis result from pronunciation_engine.
  // Preserves the full per-word + phoneme_stats payload so later screens
  // (history, progress tracking) can render the same breakdown shown in
  // the report screen.
  Future<void> storePronunciationAnalysis({
    required Map<String, dynamic> pronunciationData,
    required String audioPath,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final overall = (pronunciationData['overall_score'] as num?)?.toInt() ?? 0;
      final perWord = (pronunciationData['per_word'] as List?) ?? const [];
      final phonemeStats =
          (pronunciationData['phoneme_stats'] as Map?) ?? const {};

      final analysisData = {
        'userId': userId,
        'type': 'pronunciation',
        'timestamp': FieldValue.serverTimestamp(),
        'overallScore': overall,
        'perWord': perWord,
        'phonemeStats': phonemeStats,
        'audioPath': audioPath,
        'wordCount': perWord.length,
      };

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('analyses')
          .add(analysisData);

      print('✓ Pronunciation analysis stored successfully');
    } catch (e) {
      print('Error storing pronunciation analysis: $e');
      rethrow;
    }
  }
}