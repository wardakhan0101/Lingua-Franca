import 'package:flutter/material.dart';
import '../services/grammar_api_service.dart';
import 'grammar_report_screen.dart';
import 'fluency_screen.dart';
import 'pronunciation_report_screen.dart';

class UnifiedReportScreen extends StatelessWidget {
  final GrammarAnalysisResult grammarResult;
  final Map<String, dynamic> fluencyResult;
  final Map<String, dynamic>? pronunciationResult;
  final String? audioPath;
  final int earnedXp;

  const UnifiedReportScreen({
    super.key,
    required this.grammarResult,
    required this.fluencyResult,
    required this.audioPath,
    this.pronunciationResult,
    this.earnedXp = 0,
  });

  @override
  Widget build(BuildContext context) {
    final hasPronunciation = pronunciationResult != null;
    return DefaultTabController(
      length: hasPronunciation ? 3 : 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          title: const Text(
            "Performance Analysis",
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: const BackButton(color: Colors.black87),
          bottom: TabBar(
            labelColor: const Color(0xFF6C63FF),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF6C63FF),
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
            GrammarReportScreen(result: grammarResult, earnedXp: earnedXp),
            FluencyScreen(
              fluencyData: fluencyResult,
              audioPath: audioPath ?? '',
              earnedXp: earnedXp,
            ),
            if (hasPronunciation)
              PronunciationReportScreen(
                pronunciationData: pronunciationResult!,
                audioPath: audioPath ?? '',
                earnedXp: earnedXp,
              ),
          ],
        ),
      ),
    );
  }
}
