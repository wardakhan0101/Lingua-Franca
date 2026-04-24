import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/assessment_question.dart';

/// Fetches assessment questions from Firestore and picks random samples
/// according to whether it's an initial placement or a level-up test.
///
/// The Firestore collection is `assessment_questions`, one doc per question.
/// See [AssessmentQuestion] for the schema.
///
/// Picking rules (from the plan):
/// - **Initial assessment**: 3 questions per skill, randomly drawn from the
///   union of ALL level pools. Natural difficulty spread comes from random
///   sampling across levels.
/// - **Level-up assessment**: 3 questions per skill, drawn ONLY from the
///   target level's pool.
///
/// Total assessment size = 9 questions (3 grammar + 3 fluency + 3 pronunciation).
class AssessmentQuestionService {
  AssessmentQuestionService({FirebaseFirestore? firestore, Random? rng})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _rng = rng ?? Random();

  final FirebaseFirestore _firestore;
  final Random _rng;

  static const int questionsPerSkill = 3;

  /// Cache so we don't re-query Firestore for every sample within a session.
  List<AssessmentQuestion>? _cached;

  Future<List<AssessmentQuestion>> _fetchActive() async {
    if (_cached != null) return _cached!;
    final snap = await _firestore
        .collection('assessment_questions')
        .where('active', isEqualTo: true)
        .get();
    _cached = snap.docs.map(AssessmentQuestion.fromDoc).toList();
    debugPrint(
      '[AssessmentQuestionService] fetched ${_cached!.length} active questions',
    );
    return _cached!;
  }

  /// Sample 3 questions per skill from the union of all four level pools.
  /// Returns a flat list of 9 questions, grouped by skill in the order
  /// grammar → fluency → pronunciation.
  ///
  /// Throws [InsufficientQuestionsException] if any skill pool is empty.
  Future<List<AssessmentQuestion>> pickInitialQuestions() async {
    final all = await _fetchActive();
    final picked = <AssessmentQuestion>[];
    for (final skill in AssessmentSkill.values) {
      final pool = all.where((q) => q.skill == skill).toList();
      picked.addAll(_sample(pool, questionsPerSkill, skillLabel: skill.wire));
    }
    return picked;
  }

  /// Sample 3 questions per skill from the [targetLevel]'s pool only.
  /// Returns a flat list of 9 questions.
  Future<List<AssessmentQuestion>> pickLevelUpQuestions(
    AssessmentLevel targetLevel,
  ) async {
    final all = await _fetchActive();
    final picked = <AssessmentQuestion>[];
    for (final skill in AssessmentSkill.values) {
      final pool = all
          .where((q) => q.skill == skill && q.level == targetLevel)
          .toList();
      picked.addAll(
        _sample(
          pool,
          questionsPerSkill,
          skillLabel: '${skill.wire}/${targetLevel.wire}',
        ),
      );
    }
    return picked;
  }

  List<AssessmentQuestion> _sample(
    List<AssessmentQuestion> pool,
    int n, {
    required String skillLabel,
  }) {
    if (pool.isEmpty) {
      throw InsufficientQuestionsException(
        'No active questions for $skillLabel',
      );
    }
    // If pool has fewer than n questions, return all of them rather than
    // crashing — the assessment falls back to a shorter round.
    if (pool.length <= n) {
      debugPrint(
        '[AssessmentQuestionService] $skillLabel pool has only ${pool.length} '
        'questions (wanted $n); using all.',
      );
      return List.of(pool)..shuffle(_rng);
    }
    final indices = <int>{};
    while (indices.length < n) {
      indices.add(_rng.nextInt(pool.length));
    }
    return indices.map((i) => pool[i]).toList();
  }

  /// Invalidate the cache — useful if the Firebase console has been edited
  /// mid-session and you want a fresh pull.
  void invalidateCache() => _cached = null;
}

class InsufficientQuestionsException implements Exception {
  final String message;
  InsufficientQuestionsException(this.message);

  @override
  String toString() => 'InsufficientQuestionsException: $message';
}
