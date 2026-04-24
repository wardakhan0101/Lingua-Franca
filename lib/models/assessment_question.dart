import 'package:cloud_firestore/cloud_firestore.dart';

enum AssessmentSkill { grammar, fluency, pronunciation }

enum AssessmentLevel { beginner, intermediate, advanced, fluent }

extension AssessmentSkillX on AssessmentSkill {
  String get wire {
    switch (this) {
      case AssessmentSkill.grammar:
        return 'grammar';
      case AssessmentSkill.fluency:
        return 'fluency';
      case AssessmentSkill.pronunciation:
        return 'pronunciation';
    }
  }

  static AssessmentSkill fromWire(String s) {
    switch (s) {
      case 'grammar':
        return AssessmentSkill.grammar;
      case 'fluency':
        return AssessmentSkill.fluency;
      case 'pronunciation':
        return AssessmentSkill.pronunciation;
      default:
        throw ArgumentError('Unknown assessment skill: $s');
    }
  }
}

extension AssessmentLevelX on AssessmentLevel {
  String get wire {
    switch (this) {
      case AssessmentLevel.beginner:
        return 'beginner';
      case AssessmentLevel.intermediate:
        return 'intermediate';
      case AssessmentLevel.advanced:
        return 'advanced';
      case AssessmentLevel.fluent:
        return 'fluent';
    }
  }

  static AssessmentLevel fromWire(String s) {
    switch (s) {
      case 'beginner':
        return AssessmentLevel.beginner;
      case 'intermediate':
        return AssessmentLevel.intermediate;
      case 'advanced':
        return AssessmentLevel.advanced;
      case 'fluent':
        return AssessmentLevel.fluent;
      default:
        throw ArgumentError('Unknown assessment level: $s');
    }
  }
}

/// A single assessment question stored in the Firestore `assessment_questions`
/// collection. One question maps to one task the user completes during the
/// initial assessment or a level-up test.
class AssessmentQuestion {
  final String id;
  final AssessmentSkill skill;
  final AssessmentLevel level;
  final String prompt;
  final String instructions;

  /// Grammar questions only — tells the grammar API to additionally check
  /// that the user answered in this tense. Values: past_simple, past_perfect,
  /// present_simple, present_perfect, future_simple.
  final String? requiredTense;

  /// Pronunciation questions only — the exact sentence the user must read
  /// aloud. Sent as the transcript to the pronunciation engine.
  final String? targetSentence;

  /// Fluency questions only — minimum duration the recording must reach
  /// before we accept the answer.
  final int minDurationSeconds;

  final bool active;

  AssessmentQuestion({
    required this.id,
    required this.skill,
    required this.level,
    required this.prompt,
    this.instructions = '',
    this.requiredTense,
    this.targetSentence,
    this.minDurationSeconds = 30,
    this.active = true,
  });

  factory AssessmentQuestion.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return AssessmentQuestion(
      id: doc.id,
      skill: AssessmentSkillX.fromWire(d['skill'] as String),
      level: AssessmentLevelX.fromWire(d['level'] as String),
      prompt: (d['prompt'] as String?) ?? '',
      instructions: (d['instructions'] as String?) ?? '',
      requiredTense: d['requiredTense'] as String?,
      targetSentence: d['targetSentence'] as String?,
      minDurationSeconds: (d['minDurationSeconds'] as num?)?.toInt() ?? 30,
      active: (d['active'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'skill': skill.wire,
        'level': level.wire,
        'prompt': prompt,
        'instructions': instructions,
        if (requiredTense != null) 'requiredTense': requiredTense,
        if (targetSentence != null) 'targetSentence': targetSentence,
        if (skill == AssessmentSkill.fluency)
          'minDurationSeconds': minDurationSeconds,
        'active': active,
      };
}
