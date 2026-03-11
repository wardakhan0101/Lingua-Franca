import 'package:flutter/material.dart';
import '../services/grammar_api_service.dart';
import 'grammar_report_screen.dart';
import 'fluency_screen.dart';

class UnifiedReportScreen extends StatelessWidget {
  final GrammarAnalysisResult grammarResult;
  final Map<String, dynamic> fluencyResult;
  final String? audioPath;
  final int earnedXp;

  const UnifiedReportScreen({
    super.key,
    required this.grammarResult,
    required this.fluencyResult,
    required this.audioPath,
    this.earnedXp = 0,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
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
          bottom: const TabBar(
            labelColor: Color(0xFF6C63FF),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFF6C63FF),
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            tabs: [
              Tab(text: "Grammar"),
              Tab(text: "Fluency"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            GrammarReportScreen(result: grammarResult, earnedXp: earnedXp),
            FluencyScreen(fluencyData: fluencyResult, audioPath: audioPath ?? '', earnedXp: earnedXp),
          ],
        ),
      ),
    );
  }
}
