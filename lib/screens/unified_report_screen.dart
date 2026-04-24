import 'package:flutter/material.dart';
import '../services/grammar_api_service.dart';
import '../theme/app_colors.dart';
import 'grammar_report_screen.dart';
import 'fluency_screen.dart';
import 'pronunciation_report_screen.dart';

class UnifiedReportScreen extends StatelessWidget {
  final GrammarAnalysisResult grammarResult;
  final Map<String, dynamic> fluencyResult;
  final Map<String, dynamic>? pronunciationResult;
  final String? audioPath;
  final int earnedXp;
  // Shared id for the three analysis docs (grammar/fluency/pronunciation)
  // persisted at session completion. Null when re-opening a past report via
  // `isHistorical: true` since we're not writing anything.
  final String? sessionId;
  // When true, this is a past session being re-opened from Profile — child
  // screens skip their per-mount Firestore writes so we don't duplicate docs.
  final bool isHistorical;

  const UnifiedReportScreen({
    super.key,
    required this.grammarResult,
    required this.fluencyResult,
    required this.audioPath,
    this.pronunciationResult,
    this.earnedXp = 0,
    this.sessionId,
    this.isHistorical = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasPronunciation = pronunciationResult != null;
    return DefaultTabController(
      length: hasPronunciation ? 3 : 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text(
            "Performance Analysis",
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: const BackButton(color: Colors.black87),
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            // Smaller font + horizontal padding tightens the third tab so
            // "Pronunciation" fits alongside Grammar/Fluency without
            // clipping on narrower devices.
            labelStyle: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            labelPadding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: [
              const Tab(text: "Grammar"),
              const Tab(text: "Fluency"),
              if (hasPronunciation) const Tab(text: "Pronunciation"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            GrammarReportScreen(
              result: grammarResult,
              earnedXp: earnedXp,
              isHistorical: isHistorical,
            ),
            FluencyScreen(
              fluencyData: fluencyResult,
              audioPath: audioPath ?? '',
              earnedXp: earnedXp,
              sessionId: sessionId,
              isHistorical: isHistorical,
            ),
            if (hasPronunciation)
              PronunciationReportScreen(
                pronunciationData: pronunciationResult!,
                audioPath: audioPath ?? '',
                earnedXp: earnedXp,
                sessionId: sessionId,
                isHistorical: isHistorical,
              ),
          ],
        ),
      ),
    );
  }
}
