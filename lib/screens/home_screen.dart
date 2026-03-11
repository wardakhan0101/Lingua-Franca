import 'package:flutter/material.dart';
import 'package:lingua_franca/screens/developers_screen.dart';
import 'package:lingua_franca/screens/profile_screen.dart';
import 'package:lingua_franca/screens/timed_presentation_screen.dart';
import '../models/scenario.dart';
import '../services/gamification_service.dart';
import '../services/grammar_api_service.dart';
import '../services/fluency_api_service.dart';
import 'scenario_chat_screen.dart';
import 'accent_test_screen.dart';
import 'badges_screen.dart';

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
      const Color(0xFFD9BFFF),
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GamificationService _gamificationService = GamificationService();
  Map<String, dynamic> _userStats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserStats();
    // Warm up the Cloud Run APIs in the background.
    // This wakes up the servers before the user actually starts a session.
    GrammarApiService.analyzeText('warmup').catchError((_) {});
    // Fluency API can also be warmed up by sending a small/invalid request
    FluencyApiService.analyzeAudio('/tmp/dummy.wav').catchError((_) {});
  }

  Future<void> _loadUserStats() async {
    try {
      final stats = await _gamificationService.getUserStats();
      setState(() {
        _userStats = stats;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Error loading stats: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF8A48F0))),
      );
    }

    final int totalXp = _userStats['totalXp'] ?? 0;
    final int streak = _userStats['currentStreak'] ?? 0;
    final String level = _userStats['currentLevel'] ?? 'B1';
    final List<String> badges = List<String>.from(_userStats['badges'] ?? []);

    // Brand Colors
    final Color primaryPurple = const Color(0xFF8A48F0);
    final Color softBackground = const Color(0xFFF7F7FA);
    final Color textDark = const Color(0xFF101828);
    final Color textGrey = const Color(0xFF667085);

    return Scaffold(
      backgroundColor: softBackground,
      bottomNavigationBar: _buildBottomNavBar(context, primaryPurple),
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

                  // MAIN ACTION - This is the only "Active" looking button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () => _showPracticeModeSelection(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryPurple,
                        foregroundColor: Colors.white,
                        elevation: 8,
                        shadowColor: primaryPurple.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Start Conversation',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

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
                            color: Color(0xFF8A48F0),
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
                  const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF512F), size: 18),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      width: double.infinity,
      decoration: BoxDecoration(
        // ✨ NEW: Subtle Gradient Background (The "Fancy" Touch)
        gradient: LinearGradient(
          colors: [
            const Color(0xFFF9F5FF), // Very light purple
            const Color(0xFFF0E6FF), // Slightly deeper light purple
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        // Removed border to let gradient shine
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8A48F0).withOpacity(0.08), // Colored shadow
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome User!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF344054),
                ),
              ),
              SizedBox(height: 4),
              Text(
                "Let's start your journey.",
                style: TextStyle(color: Color(0xFF667085), fontSize: 14),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.6), // Glass-like feel
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white),
            ),
            child: Text(
              'Level $level',
              style: TextStyle(
                color: primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(Color primary, Color textDark, Color textGrey, int totalXp, String level) {
    int threshold = 2500;
    if (level == 'B2') threshold = 7500;
    if (level == 'C1') threshold = 15000;

    final double currentProgress = (totalXp / threshold).clamp(0.0, 1.0);
    final String currentProgressText = '${(currentProgress * 100).toInt()}%';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
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
                'Level $level Progress',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textGrey),
              ),
              Text(
                '$totalXp / $threshold XP',
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
                      // Track color only, no progress
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
                  color: isActive ? const Color(0xFF8A48F0) : Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF8A48F0).withOpacity(0.1) : Colors.grey.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive ? const Color(0xFF8A48F0) : Colors.grey.shade200,
                    width: 2,
                  ),
                ),
                child: isActive
                  ? const Icon(Icons.check_rounded, color: Color(0xFF8A48F0), size: 20)
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
          _buildBadge(Icons.emoji_events_rounded, 'B2 Master', badges.contains('B2 Master')),
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
          child: Icon(icon, color: isUnlocked ? const Color(0xFFD4AF37) : Colors.grey.shade400, size: 28),
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
              color: isUnlocked ? const Color(0xFF101828) : Colors.grey.shade400,
            ),
          ),
        ),
      ],
    );
  }

  // --- PRACTICE MODE SELECTION BOTTOM SHEET ---
  void _showPracticeModeSelection(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Select Practice Mode",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF101828),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Choose a high-level practice mode to get started.",
              style: TextStyle(fontSize: 14, color: Color(0xFF667085)),
            ),
            const SizedBox(height: 24),
            
            // 1. Timed Presentation
            _buildScenarioOption(
              context: context,
              icon: Icons.timer_outlined,
              title: "Timed Presentation",
              subtitle: "Speak freely on any topic with a timer",
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const TimedPresentationScreen()),
                );
              },
            ),
            
            const SizedBox(height: 12),
            
            // 2. Scenario Based Dialogs
            _buildScenarioOption(
              context: context,
              icon: Icons.chat_bubble_outline,
              title: "Scenario Based Dialogs",
              subtitle: "Practice specific real-world situations",
              onTap: () {
                Navigator.pop(context); // Close the first sheet
                _showSpecificScenarios(context); // Open the scenarios sheet
              },
            ),

            const SizedBox(height: 12),
            
            // 3. Freestyle Conversation (Locked)
            _buildScenarioOption(
              context: context,
              icon: Icons.forum_outlined,
              title: "Freestyle Conversation",
              subtitle: "Open-ended chat with AI",
              isLocked: true,
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // --- SPECIFIC SCENARIOS BOTTOM SHEET ---
  void _showSpecificScenarios(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF101828)),
                  onPressed: () {
                    Navigator.pop(context); // Close scenarios sheet
                    _showPracticeModeSelection(context); // Reopen mode sheet
                  },
                ),
                const SizedBox(width: 8),
                const Text(
                  "Scenarios",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF101828),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(left: 12.0),
              child: Text(
                "Select a specific situation to practice.",
                style: TextStyle(fontSize: 14, color: Color(0xFF667085)),
              ),
            ),
            const SizedBox(height: 24),
            
            // 1. Ordering Fast Food (MVP)
            _buildScenarioOption(
              context: context,
              icon: Icons.fastfood_outlined,
              title: "Ordering Fast Food",
              subtitle: "Practice ordering food at a drive-thru",
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => ScenarioChatScreen(
                    scenario: const Scenario(
                      id: "fast_food_1",
                      title: "Ordering Fast Food",
                      // UPDATED IN PHASE 5: Adding [END_CONVERSATION] instruction
                      systemPrompt: "You are a friendly but busy cashier at a popular fast food burger restaurant. Keep your responses short, conversational, and authentic to a fast-food drive-thru or counter experience. Do not offer more than 2-3 sentences per turn. Ask the customer for their order, clarify details if needed, and give them a total. Start by welcoming them. When the order is complete and there is nothing more to say, output the exact phrase [END_CONVERSATION] at the end of your message.",
                      initialGreeting: "Hi there! Welcome to Burger Haven. What can I get for you today?",
                    ),
                  )),
                );
              },
            ),

            const SizedBox(height: 12),
            
            // 2. Job Interview
            _buildScenarioOption(
              context: context,
              icon: Icons.work_outline,
              title: "Job Interview",
              subtitle: "Professional mock interview practice",
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => ScenarioChatScreen(
                    scenario: const Scenario(
                      id: "job_interview_1",
                      title: "Job Interview",
                      systemPrompt: "You are a senior HR manager at a reputable tech company conducting a real job interview for a junior Software Engineer role. Ask realistic behavioural and technical questions one at a time (e.g. 'Tell me about a challenging project', 'How do you handle deadlines?', 'Describe a conflict with a teammate'). Keep each response/question to 1 sentence (under 12 words). React naturally to the candidate's answers — ask a brief follow-up if their answer is vague. After 8-10 exchanges, thank them professionally, tell them the team will be in touch, then output the exact phrase [END_CONVERSATION] at the very end.",
                      initialGreeting: "Hello! Thanks for coming in. Please take a seat.",
                    ),
                  )),
                );
              },
            ),

            const SizedBox(height: 12),

            // 3. Travel & Hotel
            _buildScenarioOption(
              context: context,
              icon: Icons.flight_takeoff_outlined,
              title: "Travel & Hotel",
              subtitle: "Practice checking in and navigating travel",
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => ScenarioChatScreen(
                    scenario: const Scenario(
                      id: "travel_hotel_1",
                      title: "Travel & Hotel",
                      systemPrompt: "You are a polite hotel front-desk receptionist at a mid-range hotel. Keep every response to 1 short sentence (under 12 words). Ask one question at a time. Help the guest check in: ask for their name, confirm reservation, explain breakfast hours, and hand over the key card. After check-in is complete and there is nothing more to say, output the exact phrase [END_CONVERSATION] at the end of your final message.",
                      initialGreeting: "Good evening! Welcome to Grand Stay Hotel. How may I help you?",
                    ),
                  )),
                );
              },
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildScenarioOption({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    bool isLocked = false,
    bool isNew = false,
    VoidCallback? onTap,
  }) {
    final Color primaryPurple = const Color(0xFF8A48F0);
    
    return InkWell(
      onTap: isLocked ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isLocked ? Colors.grey.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isLocked ? Colors.grey.shade200 : Colors.grey.shade300),
          boxShadow: isLocked ? [] : [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isLocked ? Colors.grey.shade200 : primaryPurple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isLocked ? Colors.grey.shade400 : primaryPurple,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isLocked ? Colors.grey.shade500 : const Color(0xFF101828),
                        ),
                      ),
                      if (isNew) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "NEW",
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isLocked ? Colors.grey.shade400 : const Color(0xFF667085),
                    ),
                  ),
                ],
              ),
            ),
            if (isLocked)
              Icon(Icons.lock_outline, color: Colors.grey.shade400, size: 20)
            else
              Icon(Icons.arrow_forward_ios, color: Colors.grey.shade400, size: 16),
          ],
        ),
      ),
    );
  }

  // --- BOTTOM NAV BAR ---
  Widget _buildBottomNavBar(BuildContext context, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: BottomNavigationBar(
        elevation: 0,
        backgroundColor: Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: Colors.grey.shade400,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        onTap: (index) {
          if (index == 1){
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const TimedPresentationScreen(),
              ),
            );
          }
          if (index == 3) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const ProfileScreen(),
              ),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.mic_rounded), label: 'Practice'),
          BottomNavigationBarItem(icon: Icon(Icons.pie_chart_rounded), label: 'Progress'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }
}