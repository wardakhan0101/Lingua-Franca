import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'grammar_api_service.dart';

class GamificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Level Thresholds
  static const int thresholdB2 = 2500;
  static const int thresholdC1 = 7500;
  static const int thresholdC2 = 15000;

  // Get current user stats
  Future<Map<String, dynamic>> getUserStats() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return {};

    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) {
      // Initialize if not exists
      final initialData = {
        'totalXp': 0,
        'currentLevel': 'B1',
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
    final level = data['currentLevel'] as String? ?? 'B1';
    if (level == 'B2' && !currentBadges.contains('B2 Master')) {
      newBadges.add('B2 Master');
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
  Future<bool> attemptLevelUp() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return false;

    final data = await getUserStats();
    int xp = data['totalXp'] ?? 0;
    String level = data['currentLevel'] ?? 'B1';
    
    int threshold = 0;
    String nextLevel = '';
    if (level == 'B1') { threshold = thresholdB2; nextLevel = 'B2'; }
    else if (level == 'B2') { threshold = thresholdC1; nextLevel = 'C1'; }
    else if (level == 'C1') { threshold = thresholdC2; nextLevel = 'C2'; }

    if (xp < threshold) return false;

    // Here we would normally trigger an assessment. 
    // For now, let's assume this method is called after a pass/fail.
    return true; 
  }

  Future<void> handleAssessmentResult(bool passed) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final data = await getUserStats();
    String level = data['currentLevel'] ?? 'B1';
    int xp = data['totalXp'] ?? 0;

    if (passed) {
      String nextLevel = level == 'B1' ? 'B2' : (level == 'B2' ? 'C1' : 'C2');
      await _firestore.collection('users').doc(userId).update({
        'currentLevel': nextLevel,
        // Optional: Keep XP or reset? User wants to "reach another assessment stage"
        // Let's keep XP as a total.
      });
    } else {
      // Failure Penalty: -20% of the threshold
      int threshold = level == 'B1' ? thresholdB2 : (level == 'B2' ? thresholdC1 : thresholdC2);
      int penalty = (threshold * 0.20).toInt();
      await _firestore.collection('users').doc(userId).update({
        'totalXp': FieldValue.increment(-penalty),
      });
    }
  }
}
