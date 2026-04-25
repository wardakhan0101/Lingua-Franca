import 'package:flutter/material.dart';

import '../models/assessment_question.dart';
import '../services/assessment_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../widgets/app_card.dart';
import '../widgets/primary_button.dart';
import 'assessment_screen.dart';
import 'root_scaffold.dart';

/// Result page shown after the AssessmentScreen finishes grading. Animates
/// the per-skill score bars in on first frame and displays a hero placement
/// chip (initial mode) or a pass/fail header (level-up mode). Navigates home
/// using its OWN BuildContext — the assessment screen has been disposed by
/// the time this is shown, so a captured callback would point at a dead context.
class AssessmentResultScreen extends StatefulWidget {
  const AssessmentResultScreen({
    super.key,
    required this.mode,
    required this.result,
  });

  final AssessmentMode mode;
  final AssessmentResult result;

  @override
  State<AssessmentResultScreen> createState() => _AssessmentResultScreenState();
}

class _AssessmentResultScreenState extends State<AssessmentResultScreen>
    with TickerProviderStateMixin {
  late final AnimationController _revealController;
  late final Animation<double> _revealAnim;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _revealAnim = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    );
    // Slight delay so the user sees a beat before the bars fill in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealController.forward();
    });
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outcome = widget.result.outcome;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeroHeader(outcome),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCompositeCard(),
                    const SizedBox(height: AppSpacing.xl),
                    _buildSkillBreakdown(),
                    const SizedBox(height: AppSpacing.xxxl),
                    PrimaryButton(
                      label: 'Continue to Home',
                      gradient: true,
                      icon: Icons.home_rounded,
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (_) => const RootScaffold()),
                          (route) => false,
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Gradient hero with a big trophy icon and either the placement level or
  /// a pass/fail headline.
  Widget _buildHeroHeader(AssessmentOutcome outcome) {
    final isPass = outcome is PlacementOutcome ||
        (outcome is LevelUpOutcome && outcome.passed);
    final gradientColors = isPass
        ? [AppColors.primary, AppColors.primaryGradientEnd]
        : [const Color(0xFFE05757), const Color(0xFFF09F4D)];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xxxl,
      ),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            child: Icon(
              isPass ? Icons.emoji_events_rounded : Icons.shield_outlined,
              size: 48,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (outcome is PlacementOutcome) ...[
            Text(
              "You're placed at",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _capitalize(outcome.placedLevel),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ],
          if (outcome is LevelUpOutcome) ...[
            Text(
              outcome.passed
                  ? 'Welcome to ${_capitalize(outcome.targetLevel.wire)}!'
                  : 'Not quite — try again soon',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              outcome.passed
                  ? "You've been promoted."
                  : 'Needed ${outcome.passThreshold}%, got ${widget.result.composite}%. Keep practicing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompositeCard() {
    final color = _colorForScore(widget.result.composite);
    return Transform.translate(
      // Pull the card up over the gradient header for a layered look.
      offset: const Offset(0, -36),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xxl, horizontal: AppSpacing.xl,
        ),
        child: Column(
          children: [
            Text(
              'Composite Score',
              style: AppTextStyles.caption.copyWith(letterSpacing: 0.5),
            ),
            const SizedBox(height: AppSpacing.md),
            AnimatedBuilder(
              animation: _revealAnim,
              builder: (context, _) {
                final shown =
                    (widget.result.composite * _revealAnim.value).round();
                return Text(
                  '$shown%',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: -2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AnimatedBuilder(
                animation: _revealAnim,
                builder: (context, _) => LinearProgressIndicator(
                  value: (widget.result.composite / 100.0) * _revealAnim.value,
                  minHeight: 8,
                  backgroundColor: AppColors.background,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillBreakdown() {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Per-skill breakdown', style: AppTextStyles.title),
          const SizedBox(height: AppSpacing.lg),
          _buildSkillRow(
              Icons.edit_note_rounded, 'Grammar', widget.result.grammarScore),
          const SizedBox(height: AppSpacing.md),
          _buildSkillRow(Icons.mic_external_on_rounded, 'Fluency',
              widget.result.fluencyScore),
          const SizedBox(height: AppSpacing.md),
          _buildSkillRow(Icons.record_voice_over_rounded, 'Pronunciation',
              widget.result.pronunciationScore),
        ],
      ),
    );
  }

  Widget _buildSkillRow(IconData icon, String label, int score) {
    final color = _colorForScore(score);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600)),
                  AnimatedBuilder(
                    animation: _revealAnim,
                    builder: (context, _) {
                      final shown = (score * _revealAnim.value).round();
                      return Text(
                        '$shown%',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: color,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AnimatedBuilder(
                  animation: _revealAnim,
                  builder: (context, _) => LinearProgressIndicator(
                    value: (score / 100.0) * _revealAnim.value,
                    minHeight: 8,
                    backgroundColor: AppColors.background,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _colorForScore(int score) {
    if (score >= 85) return AppColors.success;
    if (score >= 70) return const Color(0xFF7BC74D);
    if (score >= 60) return AppColors.warning;
    if (score >= 50) return const Color(0xFFEC7937);
    return AppColors.danger;
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
