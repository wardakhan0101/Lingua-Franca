import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'grammar_api_service.dart';

class GamificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Level Thresholds — XP required to unlock the level-up assessment for
  // each target level. Ladder: novice → beginner → intermediate → advanced → fluent.
  static const int thresholdBeginner = 500;
  static const int thresholdIntermediate = 2500;
  static const int thresholdAdvanced = 7500;
  static const int thresholdFluent = 15000;

  // Ordered level ladder — index is level rank (0 = lowest).
  static const List<String> levelLadder = [
    'novice',
    'beginner',
    'intermediate',
    'advanced',
    'fluent',
  ];

  /// Maps a level key to the XP threshold you need to reach the NEXT level.
  /// Returns null if already at the top.
  static int? xpThresholdToReachNextFrom(String level) {
    switch (level) {
      case 'novice':
        return thresholdBeginner;
      case 'beginner':
        return thresholdIntermediate;
      case 'intermediate':
        return thresholdAdvanced;
      case 'advanced':
        return thresholdFluent;
      case 'fluent':
      default:
        return null;
    }
  }

  /// Returns the next level up from [current], or null if already at fluent.
  static String? nextLevelFrom(String current) {
    final idx = levelLadder.indexOf(current);
    if (idx < 0 || idx >= levelLadder.length - 1) return null;
    return levelLadder[idx + 1];
  }

  /// Map legacy CEFR codes (B1/B2/C1/C2) to the new friendly labels.
  /// Used during user-doc backfill.
  static String _migrateLegacyLevel(String? legacy) {
    switch (legacy) {
      case 'B1':
        return 'beginner';
      case 'B2':
        return 'intermediate';
      case 'C1':
        return 'advanced';
      case 'C2':
        return 'fluent';
      default:
        return legacy ?? 'novice';
    }
  }

  // Get current user stats
  Future<Map<String, dynamic>> getUserStats() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return {};

    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) {
      // Initialize if not exists. New signups start at `novice` and have NOT
      // completed the initial placement — AuthWrapper will route them to the
      // assessment screen before Home.
      final initialData = {
        'totalXp': 0,
        'currentLevel': 'novice',
        'currentStreak': 0,
        'longestStreak': 0,
        'lastActiveDate': null,
        'totalSessions': 0,
        'badges': [],
        'joinedAt': FieldValue.serverTimestamp(),
        // Pronunciation tracking. `firstSessionPronAvg` is null until the
        // user's first pronunciation-scored session, after which it is frozen
        // so "Accent Warrior" can measure improvement from that baseline.
        'pronunciationAvg': 0.0,
        'firstSessionPronAvg': null,
        'pronunciationScores': <int>[],
        'phonemeStats': <String, dynamic>{},
        // Assessment module.
        'hasCompletedInitialAssessment': false,
        'levelUpAttempts': <String, dynamic>{},
      };
      await _firestore.collection('users').doc(userId).set(initialData);
      // Re-read so the serverTimestamp resolves to a concrete value.
      final freshDoc = await _firestore.collection('users').doc(userId).get();
      return freshDoc.data() ?? initialData;
    }

    final data = doc.data()!;
    // Backfill fields for users that existed before these were tracked.
    final Map<String, dynamic> backfill = {};
    if (!data.containsKey('longestStreak')) {
      backfill['longestStreak'] = data['currentStreak'] ?? 0;
    }
    if (!data.containsKey('joinedAt')) {
      backfill['joinedAt'] = FieldValue.serverTimestamp();
    }
    if (!data.containsKey('pronunciationAvg')) {
      backfill['pronunciationAvg'] = 0.0;
    }
    if (!data.containsKey('firstSessionPronAvg')) {
      backfill['firstSessionPronAvg'] = null;
    }
    if (!data.containsKey('pronunciationScores')) {
      backfill['pronunciationScores'] = <int>[];
    }
    if (!data.containsKey('phonemeStats')) {
      backfill['phonemeStats'] = <String, dynamic>{};
    }
    // Migrate legacy CEFR level strings to the new friendly labels.
    final currentLevel = data['currentLevel'] as String?;
    if (currentLevel != null &&
        (currentLevel == 'B1' ||
            currentLevel == 'B2' ||
            currentLevel == 'C1' ||
            currentLevel == 'C2')) {
      backfill['currentLevel'] = _migrateLegacyLevel(currentLevel);
    }
    // Grandfather existing users — they keep their level and skip the
    // initial assessment.
    if (!data.containsKey('hasCompletedInitialAssessment')) {
      backfill['hasCompletedInitialAssessment'] = true;
    }
    if (!data.containsKey('levelUpAttempts')) {
      backfill['levelUpAttempts'] = <String, dynamic>{};
    }
    if (backfill.isNotEmpty) {
      await _firestore.collection('users').doc(userId).set(backfill, SetOptions(merge: true));
      data.addAll(backfill);
    }
    return data;
  }

  // Eagerly award every badge that doesn't depend on the grammar result,
  // so the celebration popup can fire BEFORE the multi-second grammar/
  // fluency Cloud Run calls complete. This method takes over the
  // session-count increment and streak update that used to live inside
  // `updateSessionXp`, so callers MUST run this before `updateSessionXp`
  // or those counters will never advance.
  //
  // Returns the list of newly-earned non-grammar badges. Grammar Wizard is
  // deliberately excluded — it's handled in `updateSessionXp` once the
  // grammar API result is known.
  Future<List<String>> runEagerBadgeCheck({
    required int durationSeconds,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return <String>[];

    // Snapshot pre-session state so the "first time earning this" guards
    // evaluate against the old badge list, not a half-written one.
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final data = userDoc.data() ?? {};
    final currentBadges = List<String>.from(data['badges'] ?? []);

    // Update streak FIRST so Streak Starter / Weekly Warrior check the new
    // value in this same pass.
    final newStreak = await _updateStreak(userId, data);

    // Bump session count so Persistent Learner can use the post-session
    // total. `_updateStreak` already wrote the user doc, so use `set(merge)`
    // here to avoid a lost-update race on concurrent fields.
    await _firestore.collection('users').doc(userId).set({
      'totalSessions': FieldValue.increment(1),
    }, SetOptions(merge: true));
    final newTotalSessions = (data['totalSessions'] as int? ?? 0) + 1;

    final newBadges = <String>[];
    final now = DateTime.now();

    if (durationSeconds > 180 && !currentBadges.contains('Iron Lung')) {
      newBadges.add('Iron Lung');
    }
    if ((now.hour >= 23 || now.hour < 5) &&
        !currentBadges.contains('Night Owl')) {
      newBadges.add('Night Owl');
    }
    if ((now.hour >= 5 && now.hour < 9) &&
        !currentBadges.contains('Early Bird')) {
      newBadges.add('Early Bird');
    }
    if (newStreak >= 3 && !currentBadges.contains('Streak Starter')) {
      newBadges.add('Streak Starter');
    }
    if (newStreak >= 7 && !currentBadges.contains('Weekly Warrior')) {
      newBadges.add('Weekly Warrior');
    }
    if (newTotalSessions >= 10 &&
        !currentBadges.contains('Persistent Learner')) {
      newBadges.add('Persistent Learner');
    }
    final level = _migrateLegacyLevel(data['currentLevel'] as String?);
    if (level == 'intermediate' &&
        !currentBadges.contains('Intermediate Master')) {
      newBadges.add('Intermediate Master');
    }

    if (newBadges.isNotEmpty) {
      await _firestore.collection('users').doc(userId).update({
        'badges': FieldValue.arrayUnion(newBadges),
      });
    }

    return newBadges;
  }

  // Compute XP for this session and award Grammar Wizard if applicable.
  //
  // Assumes `runEagerBadgeCheck` was called FIRST — session count and streak
  // have already been written, so this method only re-reads the user doc to
  // pick up the streak multiplier and the current XP baseline.
  //
  // Returns `earnedXp` (with streak multiplier applied) plus `newBadges`
  // which contains `['Grammar Wizard']` when freshly earned, otherwise empty.
  Future<Map<String, dynamic>> updateSessionXp({
    required GrammarAnalysisResult grammarResult,
    required Map<String, dynamic> fluencyData,
    required int durationSeconds,
    // Optional so existing callers keep working while pronunciation rolls out.
    // Pass `null` (or omit) when pronunciation analysis didn't run for this
    // session — nothing XP / badge-wise will change from pronunciation.
    int? pronunciationScore,
    Map<String, dynamic>? phonemeStats,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return {'earnedXp': 0, 'newBadges': <String>[]};

    // 1. Grammar XP
    int grammarXp = grammarResult.summary.grammarScore.toInt();
    if (grammarResult.mistakes.isEmpty) grammarXp += 20;
    grammarXp = grammarXp.clamp(0, 120);

    // 2. Fluency XP (base 50, subtract for each issue marker)
    int fluencyXp = 50;
    final annotatedTranscript =
        fluencyData['annotated_transcript'] as String? ?? '';
    fluencyXp -= _countOccurrences(annotatedTranscript, '[P-major]') * 8;
    fluencyXp -= _countOccurrences(annotatedTranscript, '[S]') * 5;
    fluencyXp -= _countOccurrences(annotatedTranscript, '[FAST]') * 3;
    fluencyXp -= _countOccurrences(annotatedTranscript, '[F]') * 2;
    fluencyXp -= _countOccurrences(annotatedTranscript, '[P-minor]') * 1;
    fluencyXp = fluencyXp.clamp(0, 50);

    // 3. Base + engagement
    int basePracticeXp = 10;
    int engagementXp = durationSeconds ~/ 10;

    // 4. Pronunciation XP — 0..40 from the score, +10 clean-delivery bonus.
    int pronunciationXp = 0;
    if (pronunciationScore != null) {
      pronunciationXp = (pronunciationScore / 2.5).toInt();
      final stats = phonemeStats ?? const <String, dynamic>{};
      final bool noPhonemeUnder70 = stats.values.every((entry) {
        if (entry is! Map) return true;
        final total = (entry['expected'] as num?)?.toInt() ?? 0;
        final correct = (entry['correct'] as num?)?.toInt() ?? 0;
        if (total == 0) return true;
        return (correct / total) >= 0.7;
      });
      if (noPhonemeUnder70 && pronunciationScore >= 60) {
        pronunciationXp += 10;
      }
      pronunciationXp = pronunciationXp.clamp(0, 50);
    }

    int totalEarnedXp =
        grammarXp + fluencyXp + basePracticeXp + engagementXp + pronunciationXp;

    // 5. Re-read doc to pick up streak value written by the eager pass.
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final data = userDoc.data() ?? {};
    final int streakResult = data['currentStreak'] as int? ?? 0;
    final double streakMultiplier = 1.0 + (streakResult.clamp(0, 5) * 0.05);
    totalEarnedXp = (totalEarnedXp * streakMultiplier).toInt();

    // 6. Write XP + pronunciation tracking fields.
    final Map<String, dynamic> updates = {
      'totalXp': FieldValue.increment(totalEarnedXp),
    };
    if (pronunciationScore != null) {
      final prevScores = List<int>.from(
        (data['pronunciationScores'] as List?)?.map(
              (e) => (e as num).toInt(),
            ) ??
            const <int>[],
      );
      final newScores = [...prevScores, pronunciationScore];
      final newAvg =
          newScores.reduce((a, b) => a + b) / newScores.length;

      updates['pronunciationScores'] = newScores;
      updates['pronunciationAvg'] = newAvg;
      if (data['firstSessionPronAvg'] == null) {
        updates['firstSessionPronAvg'] = pronunciationScore;
      }
      if (phonemeStats != null && phonemeStats.isNotEmpty) {
        final mergedPhonemeStats = _mergePhonemeStats(
          Map<String, dynamic>.from(
            data['phonemeStats'] as Map? ?? const {},
          ),
          phonemeStats,
        );
        updates['phonemeStats'] = mergedPhonemeStats;
      }
    }
    await _firestore
        .collection('users')
        .doc(userId)
        .set(updates, SetOptions(merge: true));

    // 7. Badges that depend on grammar/pronunciation results.
    final newBadges = <String>[];
    final currentBadges = List<String>.from(data['badges'] ?? []);

    if (grammarResult.mistakes.isEmpty &&
        !currentBadges.contains('Grammar Wizard')) {
      newBadges.add('Grammar Wizard');
    }

    if (pronunciationScore != null) {
      // Read post-write state for badge conditions that need fresh totals.
      final postScores = List<int>.from(
        (updates['pronunciationScores'] as List?) ?? const <int>[],
      );
      final double postAvg =
          (updates['pronunciationAvg'] as double?) ??
              ((data['pronunciationAvg'] as num?)?.toDouble() ?? 0.0);
      final double firstAvg =
          ((data['firstSessionPronAvg'] ?? updates['firstSessionPronAvg'])
                      as num?)
                  ?.toDouble() ??
              pronunciationScore.toDouble();
      final Map<String, dynamic> postPhonemeStats =
          Map<String, dynamic>.from(
        (updates['phonemeStats'] as Map?) ??
            (data['phonemeStats'] as Map? ?? const {}),
      );
      final int totalSessionsPost =
          (data['totalSessions'] as int? ?? 0);

      // Clear Speaker — first session at 80%+.
      if (postScores.length == 1 &&
          pronunciationScore >= 80 &&
          !currentBadges.contains('Clear Speaker')) {
        newBadges.add('Clear Speaker');
      }

      // Phoneme Master — 10 sessions at 85%+.
      final masterCount = postScores.where((s) => s >= 85).length;
      if (masterCount >= 10 && !currentBadges.contains('Phoneme Master')) {
        newBadges.add('Phoneme Master');
      }

      // TH Conqueror — combined correct count for /θ/ and /ð/ ≥ 20.
      final thetaCorrect = _readCorrect(postPhonemeStats, 'θ');
      final ethCorrect = _readCorrect(postPhonemeStats, 'ð');
      if (thetaCorrect + ethCorrect >= 20 &&
          !currentBadges.contains('TH Conqueror')) {
        newBadges.add('TH Conqueror');
      }

      // Accent Warrior — needs at least 4 sessions of data to be meaningful.
      if (totalSessionsPost >= 4 &&
          (postAvg - firstAvg) >= 15 &&
          !currentBadges.contains('Accent Warrior')) {
        newBadges.add('Accent Warrior');
      }
    }

    if (newBadges.isNotEmpty) {
      await _firestore.collection('users').doc(userId).update({
        'badges': FieldValue.arrayUnion(newBadges),
      });
    }

    return {
      'earnedXp': totalEarnedXp,
      'grammarXp': grammarXp,
      'fluencyXp': fluencyXp,
      'pronunciationXp': pronunciationXp,
      'streak': streakResult,
      'newBadges': newBadges,
    };
  }

  int _readCorrect(Map<String, dynamic> stats, String phoneme) {
    final entry = stats[phoneme];
    if (entry is Map) {
      return (entry['correct'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  // Merge per-session phoneme stats into the stored cumulative map.
  Map<String, dynamic> _mergePhonemeStats(
    Map<String, dynamic> existing,
    Map<String, dynamic> incoming,
  ) {
    final Map<String, dynamic> out = {
      for (final e in existing.entries)
        e.key: Map<String, dynamic>.from(e.value as Map),
    };

    incoming.forEach((phoneme, rawValue) {
      if (rawValue is! Map) return;
      final inc = Map<String, dynamic>.from(rawValue);
      final slot = out[phoneme] ?? <String, dynamic>{
        'expected': 0,
        'correct': 0,
        'substitutions': <String, dynamic>{},
      };
      slot['expected'] =
          (slot['expected'] as int? ?? 0) +
              ((inc['expected'] as num?)?.toInt() ?? 0);
      slot['correct'] =
          (slot['correct'] as int? ?? 0) +
              ((inc['correct'] as num?)?.toInt() ?? 0);

      final Map<String, dynamic> subs = Map<String, dynamic>.from(
        slot['substitutions'] as Map? ?? const {},
      );
      final incSubs = inc['substitutions'];
      if (incSubs is Map) {
        incSubs.forEach((k, v) {
          final key = k.toString();
          subs[key] = (subs[key] as int? ?? 0) + ((v as num?)?.toInt() ?? 0);
        });
      }
      slot['substitutions'] = subs;
      out[phoneme] = slot;
    });

    return out;
  }

  int _countOccurrences(String text, String marker) {
    if (text.isEmpty || marker.isEmpty) return 0;
    return (text.length - text.replaceAll(marker, '').length) ~/ marker.length;
  }

  Future<int> _updateStreak(String userId, Map<String, dynamic> data) async {
    final now = DateTime.now();
    final lastActive = (data['lastActiveDate'] as Timestamp?)?.toDate();
    int currentStreak = data['currentStreak'] as int? ?? 0;

    if (lastActive == null) {
      currentStreak = 1;
    } else {
      // Compare by local calendar day, not a 24-hour window — so practicing
      // Mon 11 PM then Tue 9 AM counts as a 2-day streak, matching user intuition.
      final today = DateTime(now.year, now.month, now.day);
      final lastDay = DateTime(lastActive.year, lastActive.month, lastActive.day);
      final difference = today.difference(lastDay).inDays;
      if (difference == 1) {
        currentStreak += 1;
      } else if (difference > 1) {
        currentStreak = 1; // Reset
      }
      // If difference is 0, already practised today — no change.
    }

    final int longestStreak = data['longestStreak'] as int? ?? 0;
    final Map<String, dynamic> updates = {
      'currentStreak': currentStreak,
      'lastActiveDate': FieldValue.serverTimestamp(),
    };
    if (currentStreak > longestStreak) {
      updates['longestStreak'] = currentStreak;
    }
    await _firestore.collection('users').doc(userId).update(updates);

    return currentStreak;
  }

  // Level Up Gateway
  /// Check whether the user has enough XP to attempt the level-up assessment
  /// for their next level. Returns a [LevelUpReadiness] with the target level
  /// and threshold, or null if the user is already at the top or below the
  /// next threshold.
  Future<LevelUpReadiness?> attemptLevelUp() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return null;

    final data = await getUserStats();
    final int xp = (data['totalXp'] as int?) ?? 0;
    final String level = _migrateLegacyLevel(data['currentLevel'] as String?);

    final String? nextLevel = nextLevelFrom(level);
    final int? threshold = xpThresholdToReachNextFrom(level);
    if (nextLevel == null || threshold == null) return null; // already fluent
    if (xp < threshold) return null;

    return LevelUpReadiness(
      currentLevel: level,
      nextLevel: nextLevel,
      threshold: threshold,
      currentXp: xp,
    );
  }

  /// Apply the result of a level-up assessment. On pass the user is promoted
  /// to the next level; on fail they lose 20% of the threshold XP. Also
  /// increments the per-target-level retry counter.
  Future<void> handleAssessmentResult(bool passed) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final data = await getUserStats();
    final String level = _migrateLegacyLevel(data['currentLevel'] as String?);
    final String? nextLevel = nextLevelFrom(level);
    final int? threshold = xpThresholdToReachNextFrom(level);
    if (nextLevel == null || threshold == null) return; // already fluent

    final Map<String, dynamic> attempts = Map<String, dynamic>.from(
      data['levelUpAttempts'] as Map? ?? const {},
    );
    attempts[nextLevel] = ((attempts[nextLevel] as num?)?.toInt() ?? 0) + 1;

    if (passed) {
      await _firestore.collection('users').doc(userId).update({
        'currentLevel': nextLevel,
        'levelUpAttempts': attempts,
        'lastAssessmentAt': FieldValue.serverTimestamp(),
      });
    } else {
      final int penalty = (threshold * 0.20).toInt();
      await _firestore.collection('users').doc(userId).update({
        'totalXp': FieldValue.increment(-penalty),
        'levelUpAttempts': attempts,
        'lastAssessmentAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Apply the result of the one-time initial placement assessment. Writes
  /// the placed level, per-skill scores, and flips
  /// `hasCompletedInitialAssessment` so AuthWrapper stops routing to the
  /// assessment screen on next launch.
  Future<void> applyInitialPlacement({
    required String placedLevel,
    required int grammarScore,
    required int fluencyScore,
    required int pronunciationScore,
    required int composite,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    await _firestore.collection('users').doc(userId).set({
      'currentLevel': placedLevel,
      'hasCompletedInitialAssessment': true,
      'lastAssessmentAt': FieldValue.serverTimestamp(),
      'initialAssessmentScores': {
        'grammar': grammarScore,
        'fluency': fluencyScore,
        'pronunciation': pronunciationScore,
        'composite': composite,
        'placedLevel': placedLevel,
        'completedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }
}

/// Describes a user's readiness for a level-up assessment.
class LevelUpReadiness {
  final String currentLevel;
  final String nextLevel;
  final int threshold;
  final int currentXp;

  const LevelUpReadiness({
    required this.currentLevel,
    required this.nextLevel,
    required this.threshold,
    required this.currentXp,
  });
}
