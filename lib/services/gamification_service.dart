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
        'lastActiveDate': null,
        'totalSessions': 0,
        'badges': [],
      };
      await _firestore.collection('users').doc(userId).set(initialData);
      return initialData;
    }
    return doc.data()!;
  }

  // Update XP after a session
  Future<Map<String, int>> updateSessionXp({
    required GrammarAnalysisResult grammarResult,
    required Map<String, dynamic> fluencyData,
    required int durationSeconds,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return {'earnedXp': 0};

    // 1. Calculate Grammar XP (Base 100)
    int grammarXp = 100;
    for (var mistake in grammarResult.mistakes) {
      if (mistake.severity.toLowerCase() == 'high') {
        grammarXp -= 10;
      } else if (mistake.severity.toLowerCase() == 'medium') {
        grammarXp -= 5;
      } else {
        grammarXp -= 2;
      }
    }
    if (grammarResult.mistakes.isEmpty) grammarXp += 20; // Perfect Bonus
    grammarXp = grammarXp.clamp(0, 120);

    // 2. Calculate Fluency XP (Base 100)
    int fluencyXp = 100;
    final annotatedTranscript = fluencyData['annotated_transcript'] as String? ?? '';
    
    // Counting markers
    fluencyXp -= _countOccurrences(annotatedTranscript, '[P-major]') * 8;
    fluencyXp -= _countOccurrences(annotatedTranscript, '[S]') * 5;
    fluencyXp -= _countOccurrences(annotatedTranscript, '[FAST]') * 3;
    fluencyXp -= _countOccurrences(annotatedTranscript, '[F]') * 2;
    fluencyXp -= _countOccurrences(annotatedTranscript, '[P-minor]') * 1;
    fluencyXp = fluencyXp.clamp(0, 100);

    // 3. Base & Duration XP
    int basePracticeXp = 50;
    int engagementXp = durationSeconds ~/ 10;

    int totalEarnedXp = grammarXp + fluencyXp + basePracticeXp + engagementXp;

    // 4. Update Streak and Multiplier
    final userDoc = await _firestore.collection('users').doc(userId).get();
    final data = userDoc.data() ?? {};
    
    int streakResult = await _updateStreak(userId, data);
    double streakMultiplier = 1.0 + (streakResult.clamp(0, 5) * 0.05);
    totalEarnedXp = (totalEarnedXp * streakMultiplier).toInt();

    // 5. Save to Firestore
    await _firestore.collection('users').doc(userId).update({
      'totalXp': FieldValue.increment(totalEarnedXp),
      'totalSessions': FieldValue.increment(1),
    });

    // Check for badges
    await _checkAndAwardBadges(userId, data, totalEarnedXp, durationSeconds, grammarResult.mistakes.isEmpty);

    return {
      'earnedXp': totalEarnedXp,
      'grammarXp': grammarXp,
      'fluencyXp': fluencyXp,
      'streak': streakResult,
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
      final difference = now.difference(lastActive).inDays;
      if (difference == 1) {
        currentStreak += 1;
      } else if (difference > 1) {
        currentStreak = 1; // Reset
      }
      // If difference is 0, do nothing (already active today)
    }

    await _firestore.collection('users').doc(userId).update({
      'currentStreak': currentStreak,
      'lastActiveDate': FieldValue.serverTimestamp(),
    });

    return currentStreak;
  }

  Future<void> _checkAndAwardBadges(String userId, Map<String, dynamic> data, int sessionXp, int duration, bool isPerfect) async {
    List<String> currentBadges = List<String>.from(data['badges'] ?? []);
    List<String> newBadges = [];

    if (duration > 180 && !currentBadges.contains('Iron Lung')) {
      newBadges.add('Iron Lung');
    }
    if (isPerfect && !currentBadges.contains('Grammar Wizard')) {
      newBadges.add('Grammar Wizard');
    }
    
    // Add more logic as needed...

    if (newBadges.isNotEmpty) {
      await _firestore.collection('users').doc(userId).update({
        'badges': FieldValue.arrayUnion(newBadges),
      });
    }
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
