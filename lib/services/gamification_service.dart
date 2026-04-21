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
    int totalEarnedXp = grammarXp + fluencyXp + basePracticeXp + engagementXp;

    // 4. Re-read doc to pick up streak value written by the eager pass.
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final data = userDoc.data() ?? {};
    final int streakResult = data['currentStreak'] as int? ?? 0;
    final double streakMultiplier = 1.0 + (streakResult.clamp(0, 5) * 0.05);
    totalEarnedXp = (totalEarnedXp * streakMultiplier).toInt();

    // 5. Write XP. Session count was already incremented by the eager pass.
    await _firestore.collection('users').doc(userId).set({
      'totalXp': FieldValue.increment(totalEarnedXp),
    }, SetOptions(merge: true));

    // 6. Grammar Wizard — the only badge that needs the grammar result.
    final newBadges = <String>[];
    final currentBadges = List<String>.from(data['badges'] ?? []);
    if (grammarResult.mistakes.isEmpty &&
        !currentBadges.contains('Grammar Wizard')) {
      newBadges.add('Grammar Wizard');
      await _firestore.collection('users').doc(userId).update({
        'badges': FieldValue.arrayUnion(['Grammar Wizard']),
      });
    }

    return {
      'earnedXp': totalEarnedXp,
      'grammarXp': grammarXp,
      'fluencyXp': fluencyXp,
      'streak': streakResult,
      'newBadges': newBadges,
    };
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
