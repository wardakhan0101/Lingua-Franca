import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lingua_franca/screens/developers_screen.dart';
import '../models/assessment_question.dart';
import '../services/gamification_service.dart';
import '../services/grammar_api_service.dart';
import '../services/fluency_api_service.dart';
import '../theme/app_colors.dart';
import 'assessment_screen.dart';
import 'badges_screen.dart';
import 'practice_hub_screen.dart';

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;
  final Color trackColor;
  final double strokeWidth;
  final List<Color> gradientColors;

  _CircularProgressPainter({
    required this.progress,

    required this.primaryColor,
    required this.trackColor,
    required this.strokeWidth,
    required this.gradientColors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;
    const double startAngle = -3.14159 / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, trackPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final progressSweepAngle = 3.14159 * 2 * progress;

    final progressPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..shader = LinearGradient(
        colors: gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);

    if (progress > 0) {
      canvas.drawArc(rect, startAngle, progressSweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.primaryColor != primaryColor;
  }
}

class GradientCircularProgress extends StatelessWidget {
  final double progress;
  final Color primaryColor;
  final Color trackColor;
  final double strokeWidth;

  const GradientCircularProgress({
    super.key,
    required this.progress,
    required this.primaryColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final gradientColors = [
      primaryColor,
      AppColors.primaryLight,
    ];

    return CustomPaint(
      painter: _CircularProgressPainter(
        progress: progress,
        primaryColor: primaryColor,
        trackColor: trackColor,
        strokeWidth: strokeWidth,
        gradientColors: gradientColors,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class RobotPainter extends CustomPainter {
  final double swingAngle;
  final double blinkValue;
  final Color primaryColor;

  RobotPainter({
    required this.swingAngle,
    required this.blinkValue,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.grey.shade400;

    // Center of the widget is the swing pivot
    final pivot = Offset(size.width / 2, 0);
    
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(swingAngle);

    // Cable/Arm from pivot to body top
    canvas.drawLine(Offset.zero, const Offset(0, 40), strokePaint);

    // Robot Body (Main Torso)
    paint.color = Colors.white;
    final bodyRect = Rect.fromCenter(center: const Offset(0, 70), width: 40, height: 50);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(8)), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(bodyRect, const Radius.circular(8)), strokePaint);

    // Accent on body
    paint.color = primaryColor.withOpacity(0.1);
    canvas.drawCircle(const Offset(0, 70), 10, paint);

    // Robot Head
    paint.color = Colors.white;
    final headRect = Rect.fromCenter(center: const Offset(0, 40), width: 30, height: 25);
    canvas.drawRRect(RRect.fromRectAndRadius(headRect, const Radius.circular(6)), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(headRect, const Radius.circular(6)), strokePaint);

    // Eyes
    paint.color = primaryColor.withOpacity(0.3 + (0.7 * blinkValue));
    canvas.drawCircle(const Offset(-7, 40), 3, paint);
    canvas.drawCircle(const Offset(7, 40), 3, paint);

    // Arms (Dynamic)
    final armAngle = swingAngle * 0.5;
    // Left Arm
    canvas.save();
    canvas.translate(-20, 60);
    canvas.rotate(0.5 + armAngle);
    canvas.drawLine(Offset.zero, const Offset(0, 20), strokePaint);
    canvas.restore();

    // Right Arm
    canvas.save();
    canvas.translate(20, 60);
    canvas.rotate(-0.5 + armAngle);
    canvas.drawLine(Offset.zero, const Offset(0, 20), strokePaint);
    canvas.restore();

    // Legs (Dynamic)
    final legAngle = swingAngle * 1.2;
    // Left Leg
    canvas.save();
    canvas.translate(-10, 95);
    canvas.rotate(legAngle);
    canvas.drawLine(Offset.zero, const Offset(0, 15), strokePaint);
    canvas.restore();

    // Right Leg
    canvas.save();
    canvas.translate(10, 95);
    canvas.rotate(legAngle * 0.8);
    canvas.drawLine(Offset.zero, const Offset(0, 15), strokePaint);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RobotPainter oldDelegate) {
    return oldDelegate.swingAngle != swingAngle || 
           oldDelegate.blinkValue != blinkValue;
  }
}

class SwingingRobot extends StatefulWidget {
  const SwingingRobot({super.key});

  @override
  State<SwingingRobot> createState() => _SwingingRobotState();
}

class _SwingingRobotState extends State<SwingingRobot> with TickerProviderStateMixin {
  late AnimationController _swingController;
  late AnimationController _blinkController;
  late Animation<double> _swingAnimation;

  @override
  void initState() {
    super.initState();
    _swingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    
    _swingAnimation = Tween<double>(begin: -0.2, end: 0.2).animate(
      CurvedAnimation(parent: _swingController, curve: Curves.easeInOut),
    );

    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _swingController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_swingAnimation, _blinkController]),
      builder: (context, child) {
        return CustomPaint(
          size: const Size(100, 120),
          painter: RobotPainter(
            swingAngle: _swingAnimation.value,
            blinkValue: _blinkController.value,
            primaryColor: AppColors.primary,
          ),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GamificationService _gamificationService = GamificationService();
  Map<String, dynamic> _userStats = {};
  bool _isLoading = true;

  // Non-null when the user's XP has crossed the next level's threshold and
  // they're eligible to take the level-up assessment. Drives the CTA banner.
  LevelUpReadiness? _levelUpReadiness;

  // Null when unknown (user hasn't set a username and has no displayName, or
  // Firestore hasn't responded yet). Scenarios fall back to their generic
  // greeting + systemPrompt when this is null.
  String? _username;

  // Live listener on users/{uid}. Replaces the old pattern of re-fetching
  // stats on every Navigator.pop — with IndexedStack tabs nothing pops,
  // so we need Firestore to push updates when another surface (session
  // completion, level-up assessment, profile edit) writes to the doc.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

  @override
  void initState() {
    super.initState();
    _loadUserStats();
    _loadUsername();
    _listenToUserDoc();
    // Warm up the Cloud Run APIs in the background.
    // This wakes up the servers before the user actually starts a session.
    GrammarApiService.analyzeText('warmup').catchError((_) {});
    // Fluency API can also be warmed up by sending a small/invalid request
    FluencyApiService.analyzeAudio('/tmp/dummy.wav').catchError((_) => <String, dynamic>{});
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    super.dispose();
  }

  void _listenToUserDoc() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) async {
      if (!mounted) return;
      final data = doc.data();
      if (data == null) return;
      // Re-evaluate level-up readiness whenever the doc changes — the new
      // totalXp may have crossed the next threshold.
      final readiness = await _gamificationService.attemptLevelUp();
      if (!mounted) return;
      setState(() {
        _userStats = data;
        _levelUpReadiness = readiness;
        _isLoading = false;
      });
    });
  }

  Future<void> _loadUserStats() async {
    try {
      final stats = await _gamificationService.getUserStats();
      // Also check whether the user has crossed the next XP threshold —
      // drives the level-up CTA banner.
      final readiness = await _gamificationService.attemptLevelUp();
      if (mounted) {
        setState(() {
          _userStats = stats;
          _levelUpReadiness = readiness;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading stats: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Fetches the user's preferred name with the same fallback chain the Profile
  // screen uses: Firestore users/{uid}.username → Firebase Auth displayName →
  // null. Silent on error — if anything goes wrong we simply don't personalize.
  Future<void> _loadUsername() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      final firestoreName = (doc.data()?['username'] as String?)?.trim();
      final authName = user.displayName?.trim();
      final resolved = (firestoreName != null && firestoreName.isNotEmpty)
          ? firestoreName
          : (authName != null && authName.isNotEmpty ? authName : null);
      if (resolved != null) {
        setState(() => _username = resolved);
      }
    } catch (e) {
      debugPrint('Could not load username (non-fatal): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final int totalXp = _userStats['totalXp'] ?? 0;
    final int streak = _userStats['currentStreak'] ?? 0;
    final String level = _userStats['currentLevel'] ?? 'novice';
    final List<String> badges = List<String>.from(_userStats['badges'] ?? []);

    // Brand Colors
    const Color primaryPurple = AppColors.primary;
    const Color softBackground = AppColors.background;
    const Color textDark = AppColors.textPrimary;
    const Color textGrey = AppColors.textSecondary;

    return Scaffold(
      backgroundColor: softBackground,
      body: RefreshIndicator(
        onRefresh: _loadUserStats,
        color: primaryPurple,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context, primaryPurple, textDark, streak, totalXp),
                  const SizedBox(height: 24),
                  _buildWelcomeBanner(primaryPurple, level),
                  const SizedBox(height: 24),

                  // Progress Card (Dynamic)
                  _buildProgressCard(primaryPurple, textDark, textGrey, totalXp, level),

                  const SizedBox(height: 24),

                  // MAIN ACTION - hero CTA to the practice hub
                  _buildStartConversationCta(primaryPurple),

                  const SizedBox(height: 32),

                  // UNIMPLEMENTED SECTION 1: Streak (Dynamic)
                  _buildSectionTitle('Weekly Practice Streak', textDark),
                  const SizedBox(height: 16),
                  _buildStreakRow(Colors.white, streak),

                  const SizedBox(height: 32),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle('Your Achievements', textDark),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => BadgesScreen(unlockedBadges: badges),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(50, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          "View All",
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildAchievementsRow(Colors.white, badges),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- WIDGET COMPONENTS ---

  Widget _buildStartConversationCta(Color primary) {
    const lighter = AppColors.primaryGradientEnd;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PracticeHubScreen()),
          );
          _loadUserStats();
        },
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primary, lighter],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(0.35),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Start Conversation',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Pick a mode",
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color primary, Color textDark, int streak, int xp) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Lingua Franca',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: primary,
            letterSpacing: -0.5,
          ),
        ),
        Row(
          children: [
            // Streak (Zero State, BUT COLORFUL ICON)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  // 🔥 RESTORED COLOR: Red/Orange for Fire
                  const Icon(Icons.local_fire_department_rounded, color: AppColors.streak, size: 18),
                  const SizedBox(width: 4),
                  Text('$streak', style: TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Points (Zero State, BUT COLORFUL ICON)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  // ⚡ RESTORED COLOR: Gold for Lightning
                  const Icon(Icons.flash_on_rounded, color: Color(0xFFFFD700), size: 18),
                  const SizedBox(width: 4),
                  Text('$xp', style: TextStyle(fontWeight: FontWeight.bold, color: textDark, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const DevelopersScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey.shade300,
                  child: Icon(Icons.bug_report_outlined, color: Colors.grey.shade500, size: 20),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWelcomeBanner(Color primary, String level) {
    // Determine dynamic greeting based on time of day. Fall back to "Learner"
    // when we don't have a username yet (fresh install, pre-Firestore-fetch,
    // or account from before the username field existed).
    final hour = DateTime.now().hour;
    final displayName = (_username != null && _username!.isNotEmpty)
        ? _username!
        : 'Learner';
    String greeting;
    if (hour < 12) {
      greeting = 'Good Morning, $displayName!';
    } else if (hour < 17) {
      greeting = 'Good Afternoon, $displayName!';
    } else {
      greeting = 'Good Evening, $displayName!';
    }

    // Rotating Tip of the Day
    final tips = [
      "Tip: Try the presentation mode to build confidence.",
      "Tip: Scenario chats help you think on your feet.",
      "Tip: Consistent practice is key to fluency.",
      "Tip: Don't worry about mistakes; keep speaking!",
    ];
    final currentTip = tips[DateTime.now().day % tips.length];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      width: double.infinity,
      decoration: BoxDecoration(
        // ✨ NEW: Subtle Gradient Background (The "Fancy" Touch)
        gradient: const LinearGradient(
          colors: [
            Color(0xFFF9F5FF), // Very light purple
            Color(0xFFF0E6FF), // Slightly deeper light purple
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        // Removed border to let gradient shine
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08), // Colored shadow
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF344054),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  currentTip,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6), // Glass-like feel
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white),
                ),
                child: Text(
                  'Level ${_displayLevel(level)}',
                  style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              Positioned(
                top: 26,
                child: Transform.scale(
                  scale: 0.6,
                  alignment: Alignment.topCenter,
                  child: const SwingingRobot(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _displayLevel(String level) {
    if (level.isEmpty) return level;
    return level[0].toUpperCase() + level.substring(1);
  }

  // Inline level-up CTA rendered inside the Progress Card when the user's
  // XP has crossed the next threshold. Replaces the old standalone gradient
  // banner — sits under the progress bar so the "bar is full → take the test"
  // narrative reads as one continuous flow instead of a second hero element.
  Widget _buildLevelUpActionRow(Color primary) {
    final readiness = _levelUpReadiness!;
    final next = _displayLevel(readiness.nextLevel);
    final targetEnum = AssessmentLevelX.fromWire(readiness.nextLevel);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: Color(0xFFEAECF0)),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AssessmentScreen(
                    mode: AssessmentMode.levelUp,
                    targetLevel: targetEnum,
                  ),
                ),
              );
              // Refresh when the user returns — pass or fail has updated the doc.
              if (mounted) _loadUserStats();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Icon(Icons.emoji_events_rounded, color: primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ready for $next — take your level-up assessment',
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, color: primary, size: 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(Color primary, Color textDark, Color textGrey, int totalXp, String level) {
    // Threshold = XP needed to unlock the next level. Null at 'fluent'
    // (already at max) → show a MAX progress state instead of a bar.
    final int? threshold =
        GamificationService.xpThresholdToReachNextFrom(level);
    final double currentProgress = threshold == null
        ? 1.0
        : (totalXp / threshold).clamp(0.0, 1.0);
    final String currentProgressText = '${(currentProgress * 100).toInt()}%';

    return Container(
      padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your Speaking Progress',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              const SizedBox(height: 12),
              // NEW: Horizontal Level Progress Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Level ${_displayLevel(level)} Progress',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textGrey),
                  ),
                  Text(
                    threshold == null ? 'MAX — $totalXp XP' : '$totalXp / $threshold XP',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: currentProgress,
                  minHeight: 10,
                  backgroundColor: const Color(0xFFF2F4F7),
                  color: primary,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Complete practice sessions to increase your score and reach the next level!',
                          style: TextStyle(fontSize: 14, color: textGrey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 2,
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          GradientCircularProgress(
                            progress: currentProgress,
                            primaryColor: primary,
                            trackColor: const Color(0xFFF2F4F7),
                            strokeWidth: 14,
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currentProgressText,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: textDark,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_levelUpReadiness != null) _buildLevelUpActionRow(primary),
            ],
          ),
    );
  }

  Widget _buildStatRow(String label, String value, double pct, Color textDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)), // Grey value
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: const Color(0xFFF2F4F7),
            // Grey progress bar to indicate empty
            color: Colors.grey.shade300,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: -0.5,
      ),
    );
  }

  Widget _buildStreakRow(Color bg, int currentStreak) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // For demonstration, let's say the last 'currentStreak' days are active.
    // In a real app, you'd track which specific days were active.
    final now = DateTime.now().weekday; // 1 (Mon) to 7 (Sun)

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (index) {
          final dayIndex = index + 1;
          bool isActive = false;
          // Simple logic: if streak is 3 and today is Wed (3), highlight Mon, Tue, Wed.
          if (currentStreak > 0 && dayIndex <= now && dayIndex > (now - currentStreak)) {
            isActive = true;
          }

          return Column(
            children: [
              Text(
                days[index],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.primary : Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primary.withOpacity(0.1) : Colors.grey.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive ? AppColors.primary : Colors.grey.shade200,
                    width: 2,
                  ),
                ),
                child: isActive
                  ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
                  : null,
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildAchievementsRow(Color bg, List<String> badges) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildBadge(Icons.timer_outlined, 'Iron Lung', badges.contains('Iron Lung')),
          _buildBadge(Icons.auto_awesome_rounded, 'Grammar Wizard', badges.contains('Grammar Wizard')),
          _buildBadge(Icons.local_fire_department_rounded, '7 Day Streak', badges.contains('Weekly Warrior')),
          _buildBadge(Icons.emoji_events_rounded, 'Intermediate', badges.contains('Intermediate Master')),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String label, bool isUnlocked) {
    return Column(
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: isUnlocked ? const Color(0xFFFFD700).withOpacity(0.1) : Colors.grey.shade100,
            shape: BoxShape.circle,
            border: isUnlocked ? Border.all(color: const Color(0xFFFFD700), width: 2) : null,
          ),
          child: Icon(icon, color: isUnlocked ? AppColors.gold : Colors.grey.shade400, size: 28),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 60,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isUnlocked ? AppColors.textPrimary : Colors.grey.shade400,
            ),
          ),
        ),
      ],
    );
  }

}