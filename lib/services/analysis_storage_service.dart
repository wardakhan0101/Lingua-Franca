import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'grammar_api_service.dart';

/// Per-session analyses persisted under `users/{uid}/analyses`.
///
/// Each session writes three docs (one per `type`: `grammar` | `fluency` |
/// `pronunciation`) sharing the same `sessionId`. The `sessionId` is how
/// `fetchLatestSession` joins the three docs back into a single bundle —
/// before it existed, the Profile screen had no reliable way to ask "show me
/// the latest *session*" rather than "the latest grammar doc" and risked
/// stitching together mismatched docs by timestamp proximity.
class AnalysisStorageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Store fluency analysis result.
  //
  // Persists the *full* fluency payload (annotated transcript, detected
  // fillers, stutters, pauses, fast phrases) so a historical session can be
  // re-rendered with every marker intact. `fluencyScore` is the final 0–100
  // score shown on Profile.
  Future<void> storeFluencyAnalysis({
    required String sessionId,
    required Map<String, dynamic> fluencyData,
    required String audioPath,
    required int fluencyScore,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final transcript = fluencyData['transcript'] as String? ?? '';
      final annotated =
          fluencyData['annotated_transcript'] as String? ?? transcript;
      final issues = (fluencyData['fluency_issues'] as List?) ?? const [];
      final fillers = (fluencyData['detected_fillers'] as List?) ?? const [];
      final stutters = (fluencyData['stutters'] as List?) ?? const [];
      final pauses = (fluencyData['pauses'] as List?) ?? const [];
      final fastPhrases = (fluencyData['fast_phrases'] as List?) ?? const [];

      final analysisData = {
        'userId': userId,
        'type': 'fluency',
        'sessionId': sessionId,
        'timestamp': FieldValue.serverTimestamp(),
        'transcript': transcript,
        'annotatedTranscript': annotated,
        'fluencyIssues': issues,
        'detectedFillers': fillers,
        'stutters': stutters,
        'pauses': pauses,
        'fastPhrases': fastPhrases,
        'issueCount': issues.length,
        'fluencyScore': fluencyScore,
        'audioPath': audioPath,
      };

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('analyses')
          .add(analysisData);
    } catch (e) {
      debugPrint('Error storing fluency analysis: $e');
      rethrow;
    }
  }

  // Store grammar analysis result.
  //
  // Previously had zero callers — grammar was the only engine whose output
  // never reached Firestore. Now invoked from the session-completion path
  // alongside the other two, so a session has a complete record.
  Future<void> storeGrammarAnalysis({
    required String sessionId,
    required GrammarAnalysisResult result,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final analysisData = {
        'userId': userId,
        'type': 'grammar',
        'sessionId': sessionId,
        'timestamp': FieldValue.serverTimestamp(),
        // Top-level derived fields for cheap queries / Profile display.
        'grammarScore': result.summary.grammarScore,
        'totalMistakes': result.summary.totalMistakes,
        // Full payload so we can rebuild GrammarAnalysisResult via fromJson.
        'payload': result.toJson(),
      };

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('analyses')
          .add(analysisData);
    } catch (e) {
      debugPrint('Error storing grammar analysis: $e');
      rethrow;
    }
  }

  // Store pronunciation analysis result from pronunciation_engine.
  // Preserves the full per-word + phoneme_stats payload so later screens
  // (history, progress tracking) can render the same breakdown shown in
  // the report screen.
  Future<void> storePronunciationAnalysis({
    required String sessionId,
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
        'sessionId': sessionId,
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
    } catch (e) {
      debugPrint('Error storing pronunciation analysis: $e');
      rethrow;
    }
  }

  // Read API used by the Profile "Latest Session" card.
  //
  // Deliberately uses a single-field orderBy (timestamp) so Firestore's
  // auto-created single-field indexes are enough — an earlier version
  // combined `where('type') + orderBy('timestamp')` which silently failed
  // without a manually-created composite index and left the Profile card
  // blank. We instead pull the 30 most-recent docs (~10 sessions worth) and
  // filter client-side.
  Future<LatestSessionBundle?> fetchLatestSession() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return null;
    try {
      final recent = await _firestore
          .collection('users')
          .doc(userId)
          .collection('analyses')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();
      if (recent.docs.isEmpty) return null;

      // Grammar is the only type guaranteed to exist for every session
      // (fluency is conditional on audio, pronunciation on the pron service
      // being reachable). The latest grammar doc defines the "latest session".
      Map<String, dynamic>? grammarData;
      for (final doc in recent.docs) {
        final data = doc.data();
        if (data['type'] == 'grammar') {
          grammarData = data;
          break;
        }
      }
      if (grammarData == null) return null;

      final sessionId = grammarData['sessionId'] as String?;
      if (sessionId == null) return null;

      Map<String, dynamic>? fluencyData;
      Map<String, dynamic>? pronunciationData;
      for (final doc in recent.docs) {
        final data = doc.data();
        if (data['sessionId'] != sessionId) continue;
        if (data['type'] == 'fluency') fluencyData = data;
        if (data['type'] == 'pronunciation') pronunciationData = data;
      }

      final timestamp = (grammarData['timestamp'] as Timestamp?)?.toDate();

      return LatestSessionBundle(
        sessionId: sessionId,
        timestamp: timestamp,
        grammarScore: (grammarData['grammarScore'] as num?)?.toDouble(),
        fluencyScore: (fluencyData?['fluencyScore'] as num?)?.toInt(),
        pronunciationScore:
            (pronunciationData?['overallScore'] as num?)?.toInt(),
        grammarPayload: grammarData['payload'] as Map<String, dynamic>?,
        fluencyDoc: fluencyData,
        pronunciationDoc: pronunciationData,
      );
    } catch (e) {
      debugPrint('Error fetching latest session: $e');
      return null;
    }
  }
}

/// Joined view of the three per-session docs. Null score fields mean the
/// corresponding engine didn't run for that session (e.g. pronunciation
/// service unreachable) — the Profile card shows "—" in that slot.
class LatestSessionBundle {
  final String sessionId;
  final DateTime? timestamp;
  final double? grammarScore;
  final int? fluencyScore;
  final int? pronunciationScore;
  final Map<String, dynamic>? grammarPayload;
  final Map<String, dynamic>? fluencyDoc;
  final Map<String, dynamic>? pronunciationDoc;

  LatestSessionBundle({
    required this.sessionId,
    required this.timestamp,
    required this.grammarScore,
    required this.fluencyScore,
    required this.pronunciationScore,
    required this.grammarPayload,
    required this.fluencyDoc,
    required this.pronunciationDoc,
  });

  // Rebuilds the raw map UnifiedReportScreen / FluencyScreen expect.
  // We stored each field separately, so reassemble them under the original
  // snake_case keys the screen reads from `widget.fluencyData`.
  Map<String, dynamic>? get fluencyResult {
    final doc = fluencyDoc;
    if (doc == null) return null;
    return {
      'transcript': doc['transcript'] ?? '',
      'annotated_transcript': doc['annotatedTranscript'] ?? doc['transcript'] ?? '',
      'fluency_issues': doc['fluencyIssues'] ?? const [],
      'detected_fillers': doc['detectedFillers'] ?? const [],
      'stutters': doc['stutters'] ?? const [],
      'pauses': doc['pauses'] ?? const [],
      'fast_phrases': doc['fastPhrases'] ?? const [],
    };
  }

  // Mirror of the fresh API response shape expected by PronunciationReportScreen.
  Map<String, dynamic>? get pronunciationResult {
    final doc = pronunciationDoc;
    if (doc == null) return null;
    return {
      'overall_score': doc['overallScore'] ?? 0,
      'per_word': doc['perWord'] ?? const [],
      'phoneme_stats': doc['phonemeStats'] ?? const {},
    };
  }

  String? get audioPath =>
      (pronunciationDoc?['audioPath'] ?? fluencyDoc?['audioPath']) as String?;
}
