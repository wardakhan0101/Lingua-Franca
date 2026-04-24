import 'package:flutter/foundation.dart';

import '../models/assessment_question.dart';
import 'fluency_api_service.dart';
import 'grammar_api_service.dart';
import 'pronunciation_api_service.dart';

/// One user answer for one [AssessmentQuestion]. Construct via the named
/// factories so required fields per skill are enforced.
class UserAnswer {
  final AssessmentQuestion question;
  final String? text; // grammar: the typed answer
  final String? audioPath; // fluency + pronunciation: path to recorded WAV

  const UserAnswer._({required this.question, this.text, this.audioPath});

  factory UserAnswer.grammar(AssessmentQuestion q, String text) =>
      UserAnswer._(question: q, text: text);

  factory UserAnswer.fluency(AssessmentQuestion q, String audioPath) =>
      UserAnswer._(question: q, audioPath: audioPath);

  factory UserAnswer.pronunciation(AssessmentQuestion q, String audioPath) =>
      UserAnswer._(question: q, audioPath: audioPath);
}

/// Placement-band / pass-threshold knobs. Kept in one place so they line up
/// with the gamification refactor later.
class AssessmentBands {
  AssessmentBands._();

  /// Initial-assessment placement: composite score → level label.
  /// <50 = novice, 50–59 beginner, 60–69 intermediate, 70–84 advanced, 85+ fluent.
  static String placementFromComposite(int composite) {
    if (composite >= 85) return 'fluent';
    if (composite >= 70) return 'advanced';
    if (composite >= 60) return 'intermediate';
    if (composite >= 50) return 'beginner';
    return 'novice';
  }

  /// Level-up pass threshold: the floor of the target level's band.
  static int passThresholdFor(AssessmentLevel target) {
    switch (target) {
      case AssessmentLevel.beginner:
        return 50;
      case AssessmentLevel.intermediate:
        return 60;
      case AssessmentLevel.advanced:
        return 70;
      case AssessmentLevel.fluent:
        return 85;
    }
  }
}

/// Outcome of an assessment run. Sealed-ish — either a placement (initial
/// flow) or a level-up verdict.
abstract class AssessmentOutcome {
  const AssessmentOutcome();
}

class PlacementOutcome extends AssessmentOutcome {
  /// One of 'novice' | 'beginner' | 'intermediate' | 'advanced' | 'fluent'.
  final String placedLevel;
  const PlacementOutcome(this.placedLevel);
}

class LevelUpOutcome extends AssessmentOutcome {
  final bool passed;
  final AssessmentLevel targetLevel;
  final int passThreshold;
  const LevelUpOutcome({
    required this.passed,
    required this.targetLevel,
    required this.passThreshold,
  });
}

/// Full result of a run — per-skill averages, composite, and outcome.
class AssessmentResult {
  final int grammarScore;
  final int fluencyScore;
  final int pronunciationScore;
  final int composite;
  final AssessmentOutcome outcome;

  /// Flat list of per-question scores, in the same order the answers were
  /// submitted. Useful for the result screen breakdown.
  final List<int> perQuestionScores;

  const AssessmentResult({
    required this.grammarScore,
    required this.fluencyScore,
    required this.pronunciationScore,
    required this.composite,
    required this.outcome,
    required this.perQuestionScores,
  });
}

/// Orchestrates a full assessment run. Reuses the three existing analyzer
/// services — no new backend — plus the new `required_tense` field on the
/// grammar API to grade tense-specific questions.
class AssessmentService {
  /// Grade an initial placement assessment. [answers] must contain 9 entries
  /// (3 per skill) drawn via
  /// `AssessmentQuestionService.pickInitialQuestions()`.
  Future<AssessmentResult> gradeInitial(List<UserAnswer> answers) async {
    final scored = await _gradeAll(answers);
    final composite = _composite(scored.grammar, scored.fluency, scored.pronunciation);
    return AssessmentResult(
      grammarScore: scored.grammar,
      fluencyScore: scored.fluency,
      pronunciationScore: scored.pronunciation,
      composite: composite,
      outcome: PlacementOutcome(AssessmentBands.placementFromComposite(composite)),
      perQuestionScores: scored.perQuestion,
    );
  }

  /// Grade a level-up attempt. [answers] must contain 9 entries from the
  /// [targetLevel]'s pool only.
  Future<AssessmentResult> gradeLevelUp(
    List<UserAnswer> answers,
    AssessmentLevel targetLevel,
  ) async {
    final scored = await _gradeAll(answers);
    final composite = _composite(scored.grammar, scored.fluency, scored.pronunciation);
    final threshold = AssessmentBands.passThresholdFor(targetLevel);
    return AssessmentResult(
      grammarScore: scored.grammar,
      fluencyScore: scored.fluency,
      pronunciationScore: scored.pronunciation,
      composite: composite,
      outcome: LevelUpOutcome(
        passed: composite >= threshold,
        targetLevel: targetLevel,
        passThreshold: threshold,
      ),
      perQuestionScores: scored.perQuestion,
    );
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  Future<_GradedRun> _gradeAll(List<UserAnswer> answers) async {
    // Score each answer in answer order. Skill groups are graded concurrently
    // so we don't pay 9× serial network latency.
    final futures = <Future<_Scored>>[];
    for (final a in answers) {
      futures.add(_gradeAnswer(a));
    }
    final scored = await Future.wait(futures);

    // Aggregate per skill.
    int grammarSum = 0, grammarCount = 0;
    int fluencySum = 0, fluencyCount = 0;
    int pronSum = 0, pronCount = 0;
    for (final s in scored) {
      switch (s.skill) {
        case AssessmentSkill.grammar:
          grammarSum += s.score;
          grammarCount++;
          break;
        case AssessmentSkill.fluency:
          fluencySum += s.score;
          fluencyCount++;
          break;
        case AssessmentSkill.pronunciation:
          pronSum += s.score;
          pronCount++;
          break;
      }
    }
    return _GradedRun(
      grammar: _avg(grammarSum, grammarCount),
      fluency: _avg(fluencySum, fluencyCount),
      pronunciation: _avg(pronSum, pronCount),
      perQuestion: scored.map((s) => s.score).toList(),
    );
  }

  Future<_Scored> _gradeAnswer(UserAnswer a) async {
    final skill = a.question.skill;
    switch (skill) {
      case AssessmentSkill.grammar:
        return _Scored(skill, await _gradeGrammar(a));
      case AssessmentSkill.fluency:
        return _Scored(skill, await _gradeFluency(a));
      case AssessmentSkill.pronunciation:
        return _Scored(skill, await _gradePronunciation(a));
    }
  }

  Future<int> _gradeGrammar(UserAnswer a) async {
    final text = a.text?.trim() ?? '';
    if (text.isEmpty) return 0;

    final result = await GrammarApiService.analyzeText(
      text,
      requiredTense: a.question.requiredTense,
    );

    double score = result.summary.grammarScore;

    // Blend tense-compliance into the grammar score when the question
    // specified a required tense AND the answer had enough verbs to judge.
    // Formula from the plan: effective = raw * (0.5 + 0.5 * percent).
    // Full compliance (1.0) → no penalty. Zero compliance → score halved.
    final tc = result.summary.tenseCompliance;
    if (tc != null && tc.totalVerbs >= 2) {
      score = score * (0.5 + 0.5 * tc.percent);
    }

    return score.round().clamp(0, 100);
  }

  Future<int> _gradeFluency(UserAnswer a) async {
    final path = a.audioPath ?? '';
    if (path.isEmpty) return 0;

    final fluencyJson = await FluencyApiService.analyzeAudio(path);
    final annotated = (fluencyJson['annotated_transcript'] as String?) ?? '';
    return _scoreFluencyAnnotation(annotated);
  }

  Future<int> _gradePronunciation(UserAnswer a) async {
    final path = a.audioPath ?? '';
    final target = a.question.targetSentence ?? '';
    if (path.isEmpty || target.isEmpty) return 0;

    // Pronunciation engine needs whisper_words from the fluency engine — same
    // chain used by scenario_chat_screen per-turn pronunciation.
    final fluencyJson = await FluencyApiService.analyzeAudio(path);
    final rawWhisper = fluencyJson['whisper_words'];
    final whisperWords = (rawWhisper is List)
        ? rawWhisper
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    if (whisperWords.isEmpty) {
      debugPrint(
        '[AssessmentService] fluency returned no whisper_words for pronunciation'
        ' question ${a.question.id}; scoring 0.',
      );
      return 0;
    }

    final pronJson = await PronunciationApiService.analyzePronunciation(
      audioPath: path,
      transcript: target,
      whisperWords: whisperWords,
    );
    final overall = pronJson['overall_score'];
    return (overall is num) ? overall.toInt().clamp(0, 100) : 0;
  }

  /// Scale 0–100 version of the fluency-XP formula used at
  /// `gamification_service.dart:176-181`. Multipliers are ~2× to fit the
  /// full 0–100 range instead of the XP 0–50 range.
  static int _scoreFluencyAnnotation(String annotated) {
    int score = 100;
    score -= _count(annotated, '[P-major]') * 10;
    score -= _count(annotated, '[S]') * 6;
    score -= _count(annotated, '[FAST]') * 4;
    score -= _count(annotated, '[F]') * 3;
    score -= _count(annotated, '[P-minor]') * 2;
    return score.clamp(0, 100);
  }

  static int _count(String haystack, String needle) {
    if (needle.isEmpty) return 0;
    int count = 0;
    int i = 0;
    while (true) {
      final idx = haystack.indexOf(needle, i);
      if (idx == -1) break;
      count++;
      i = idx + needle.length;
    }
    return count;
  }

  static int _avg(int sum, int count) {
    if (count == 0) return 0;
    return (sum / count).round();
  }

  static int _composite(int grammar, int fluency, int pronunciation) =>
      ((grammar + fluency + pronunciation) / 3).round();
}

class _Scored {
  final AssessmentSkill skill;
  final int score;
  const _Scored(this.skill, this.score);
}

class _GradedRun {
  final int grammar;
  final int fluency;
  final int pronunciation;
  final List<int> perQuestion;
  const _GradedRun({
    required this.grammar,
    required this.fluency,
    required this.pronunciation,
    required this.perQuestion,
  });
}
