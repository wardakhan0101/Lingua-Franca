import 'package:flutter/material.dart';

import '../models/assessment_question.dart';
import '../services/assessment_service.dart';
import 'assessment_screen.dart';

/// Result page shown after the AssessmentScreen finishes grading. Displays
/// per-skill scores, composite, and either a placement band (initial) or a
/// pass/fail verdict (level-up). The [onContinue] callback handles going
/// home; the AssessmentScreen supplies this so the whole assessment flow
/// can be popped from the back-stack cleanly.
class AssessmentResultScreen extends StatelessWidget {
  const AssessmentResultScreen({
    super.key,
    required this.mode,
    required this.result,
    required this.onContinue,
  });

  final AssessmentMode mode;
  final AssessmentResult result;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final outcome = result.outcome;
    final isInitial = mode == AssessmentMode.initial;

    return Scaffold(
      appBar: AppBar(
        title: Text(isInitial ? 'Your placement' : 'Level-up result'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              if (outcome is PlacementOutcome) _buildPlacementHeader(outcome),
              if (outcome is LevelUpOutcome) _buildLevelUpHeader(outcome),
              const SizedBox(height: 24),
              _buildCompositeCard(),
              const SizedBox(height: 16),
              _buildSkillRow('Grammar', result.grammarScore),
              _buildSkillRow('Fluency', result.fluencyScore),
              _buildSkillRow('Pronunciation', result.pronunciationScore),
              const Spacer(),
              ElevatedButton(
                onPressed: onContinue,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Continue to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlacementHeader(PlacementOutcome outcome) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.emoji_events, size: 56, color: Colors.amber),
        const SizedBox(height: 12),
        const Text(
          'You\'re placed at',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          _capitalize(outcome.placedLevel),
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _buildLevelUpHeader(LevelUpOutcome outcome) {
    final target = _capitalize(outcome.targetLevel.wire);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          outcome.passed ? Icons.check_circle : Icons.highlight_off,
          size: 56,
          color: outcome.passed ? Colors.green : Colors.redAccent,
        ),
        const SizedBox(height: 12),
        Text(
          outcome.passed ? 'Welcome to $target!' : 'Not quite — try again soon',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          outcome.passed
              ? 'You\'ve been promoted.'
              : 'You needed ${outcome.passThreshold}% composite; you got ${result.composite}%. '
                  'You\'ve lost 20% of the threshold XP as a penalty — keep practicing and try again later.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCompositeCard() {
    final color = _colorForScore(result.composite);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Text('Composite score', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Text(
            '${result.composite}%',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillRow(String label, int score) {
    final color = _colorForScore(score);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: const TextStyle(fontSize: 16)),
          ),
          Expanded(
            flex: 5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: score / 100.0,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            child: Text(
              '$score%',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForScore(int score) {
    if (score >= 85) return Colors.green;
    if (score >= 70) return Colors.lightGreen;
    if (score >= 60) return Colors.orange;
    if (score >= 50) return Colors.deepOrange;
    return Colors.red;
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
