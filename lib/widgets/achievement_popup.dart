import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/badge_definitions.dart';

// Celebration dialog shown when the user earns a new badge. Styling mirrors
// `_buildBadgeCard` in `badges_screen.dart` so the reveal matches the icon
// the user will see later in their badges list.
class AchievementPopup extends StatefulWidget {
  final BadgeModel badge;

  const AchievementPopup({super.key, required this.badge});

  @override
  State<AchievementPopup> createState() => _AchievementPopupState();
}

class _AchievementPopupState extends State<AchievementPopup>
    with SingleTickerProviderStateMixin {
  static const Color _primaryPurple = Color(0xFF8A48F0);
  static const Color _textDark = Color(0xFF101828);
  static const Color _textGrey = Color(0xFF667085);

  // Bright, complementary confetti palette. Keep these independent of the
  // badge color so every celebration feels festive regardless of which badge
  // was earned.
  static const List<Color> _confettiPalette = [
    Color(0xFFFFD54F), // amber
    Color(0xFFFF80AB), // pink
    Color(0xFF64B5F6), // blue
    Color(0xFFAED581), // lime
    Color(0xFFBA68C8), // purple
    Color(0xFFFFB74D), // orange
    Color(0xFF4DD0E1), // cyan
  ];

  late final AnimationController _confettiController;
  late final List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();

    // Deterministic-per-instance confetti: each popup gets its own random
    // spray, but within one popup the particles don't re-roll on every frame.
    final rand = math.Random();
    _particles = List.generate(36, (_) {
      return _ConfettiParticle(
        angle: rand.nextDouble() * 2 * math.pi,
        speed: 120 + rand.nextDouble() * 200,
        color: _confettiPalette[rand.nextInt(_confettiPalette.length)],
        size: 4 + rand.nextDouble() * 4,
        spin: rand.nextDouble() * 2 * math.pi,
      );
    });

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      // ClipRRect keeps the confetti from bleeding past the card's rounded
      // corners — visually cleaner than letting particles float in mid-air
      // around the dialog.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Confetti layer — painted behind the content, non-interactive.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confettiController,
                  builder: (_, __) {
                    return CustomPaint(
                      painter: _ConfettiPainter(
                        progress: _confettiController.value,
                        particles: _particles,
                      ),
                    );
                  },
                ),
              ),
            ),
            // Main content.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Scale-in icon with a glow pulse layered underneath for
                  // extra life. The pulse uses the same controller so the
                  // timing stays tightly linked to the entrance.
                  AnimatedBuilder(
                    animation: _confettiController,
                    builder: (_, __) {
                      // Pulse: 0 → 1 → 0 over the first 700 ms, then static.
                      final t = _confettiController.value;
                      final pulse = t < 0.5
                          ? (t * 2).clamp(0.0, 1.0)
                          : (1 - (t - 0.5) * 2).clamp(0.0, 1.0);
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: widget.badge.color
                                  .withOpacity(0.35 * pulse),
                              blurRadius: 28 + pulse * 10,
                              spreadRadius: 4 + pulse * 6,
                            ),
                          ],
                        ),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 650),
                          curve: Curves.elasticOut,
                          builder: (_, s, child) => Transform.scale(
                            scale: s.clamp(0.0, 1.2),
                            child: child,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: widget.badge.color.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.badge.icon,
                              size: 48,
                              color: widget.badge.color,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Achievement Unlocked',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: _primaryPurple,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.badge.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      widget.badge.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _textGrey,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryPurple,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Awesome!',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfettiParticle {
  final double angle;
  final double speed;
  final Color color;
  final double size;
  final double spin;

  const _ConfettiParticle({
    required this.angle,
    required this.speed,
    required this.color,
    required this.size,
    required this.spin,
  });
}

// Paints a one-shot confetti burst from the upper-center of the canvas
// (roughly where the badge icon sits). Each particle travels on its own
// radial trajectory with gravity pulling it down and a fade-out in the last
// 40% of the animation.
class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_ConfettiParticle> particles;

  _ConfettiPainter({required this.progress, required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    // Burst origin near the icon's vertical position inside the dialog.
    final origin = Offset(size.width / 2, size.height * 0.28);

    for (final p in particles) {
      final dx = math.cos(p.angle) * p.speed * progress;
      final dy = math.sin(p.angle) * p.speed * progress +
          progress * progress * 160; // gravity pulls everything down

      final pos = origin + Offset(dx, dy);

      // Fade out over the last 40% so the dialog is quiet by the time the
      // user reads the description.
      final opacity = progress < 0.6
          ? 1.0
          : ((1 - progress) / 0.4).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(p.spin + progress * 4 * math.pi);
      // Rectangular shape reads as confetti; a circle would look like a bubble.
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.45,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

// Show each newly-earned badge as a sequential dialog. Awaits each popup so
// multi-badge sessions (e.g., Iron Lung + Grammar Wizard + Early Bird on the
// same morning) feel like a chain of little celebrations. Unknown badge names
// are skipped so a stale name in Firestore can never crash the caller.
Future<void> showAchievementQueue(
  BuildContext context,
  List<String> badgeNames,
) async {
  for (final name in badgeNames) {
    final badge = badgeByName(name);
    if (badge == null) continue;
    if (!context.mounted) return;
    HapticFeedback.mediumImpact();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AchievementPopup(badge: badge),
    );
  }
}
