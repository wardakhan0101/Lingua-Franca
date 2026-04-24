import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/scenario.dart';
import '../theme/app_colors.dart';
import '../widgets/section_header.dart';
import 'scenario_chat_screen.dart';
import 'timed_presentation_screen.dart';

class PracticeHubScreen extends StatefulWidget {
  const PracticeHubScreen({super.key});

  @override
  State<PracticeHubScreen> createState() => _PracticeHubScreenState();
}

class _PracticeHubScreenState extends State<PracticeHubScreen> {
  static const Color _primaryPurple = AppColors.primary;
  static const Color _softBg = AppColors.background;
  static const Color _textDark = AppColors.textPrimary;
  static const Color _textGrey = AppColors.textSecondary;

  String? _username;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

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
      debugPrint('Could not load username in PracticeHub (non-fatal): $e');
    }
  }

  String _withUserContext(String systemPrompt) {
    final name = _username;
    if (name == null || name.isEmpty) return systemPrompt;
    return '$systemPrompt\n\n'
        'You are talking with $name. Use their name naturally when it fits the '
        'scene, but do not force it or overuse it.';
  }

  // --- Scenario factories ---------------------------------------------------

  Scenario _buildFastFoodScenario() => Scenario(
        id: 'fast_food_1',
        title: 'Ordering Fast Food',
        systemPrompt: _withUserContext(
          "You are a friendly but busy cashier at a popular fast food burger restaurant. Keep your responses extremely short and conversational. You MUST respond with only 1 short sentence per turn (maximum 10 words). Ask the customer for their order, clarify details if needed, and give them a total. Start by welcoming them in one short sentence. When the order is complete and there is nothing more to say, output the exact phrase [END_CONVERSATION] at the end of your message.",
        ),
        initialGreeting:
            "Hi there! Welcome to Burger Haven. What can I get for you today?",
      );

  Scenario _buildJobInterviewScenario() => Scenario(
        id: 'job_interview_1',
        title: 'Job Interview',
        systemPrompt: _withUserContext(
          "You are a senior HR manager at a reputable tech company conducting a real job interview for a junior Software Engineer role. Ask realistic behavioural and technical questions one at a time (e.g. 'Tell me about a challenging project', 'How do you handle deadlines?', 'Describe a conflict with a teammate'). Keep each response/question to 1 sentence (under 12 words). React naturally to the candidate's answers — ask a brief follow-up if their answer is vague. After 8-10 exchanges, thank them professionally, tell them the team will be in touch, then output the exact phrase [END_CONVERSATION] at the very end.",
        ),
        initialGreeting:
            "Hello! Please take a seat. Tell me about your technical background.",
      );

  Scenario _buildHotelScenario() => Scenario(
        id: 'travel_hotel_1',
        title: 'Travel & Hotel',
        systemPrompt: _withUserContext(
          "You are a polite hotel front-desk receptionist at a mid-range hotel. Keep every response to 1 short sentence (under 12 words). Ask one question at a time. Help the guest check in: ask for their name, confirm reservation, explain breakfast hours, and hand over the key card. After check-in is complete and there is nothing more to say, output the exact phrase [END_CONVERSATION] at the end of your final message.",
        ),
        initialGreeting:
            "Good evening! Welcome to Grand Stay Hotel. How may I help you?",
      );

  Scenario _buildDoctorVisitScenario() => Scenario(
        id: 'doctor_visit_1',
        title: "Doctor's Visit",
        systemPrompt: _withUserContext(
          "You are a calm, attentive general practitioner seeing a patient for a routine appointment. Keep every reply to 1 short sentence (under 12 words). Ask one focused question at a time about symptoms — what, where, when it started, pain level, medications, allergies. React empathetically but professionally. After 8-10 exchanges, summarize in one sentence what you recommend (rest, prescription, follow-up test, etc.), then output the exact phrase [END_CONVERSATION] at the very end.",
        ),
        initialGreeting:
            "Hello! Please have a seat. What brings you in today?",
      );

  Scenario _buildCustomerServiceScenario() => Scenario(
        id: 'customer_service_1',
        title: 'Customer Service Call',
        systemPrompt: _withUserContext(
          "You are a polite, procedural customer support agent for a telecom/internet company answering a phone call. Keep every reply to 1 short sentence (under 12 words). Greet the caller, ask for their account name, ask what the issue is, then work through it one step at a time (basic troubleshooting, offer a refund/replacement/engineer visit, confirm next steps). Stay professional and reassuring. After 8-10 exchanges, confirm the resolution and a ticket/reference number, then output the exact phrase [END_CONVERSATION] at the very end.",
        ),
        initialGreeting:
            "Thanks for calling SwiftConnect support. How can I help you today?",
      );

  Scenario _buildFreestyleScenario() {
    final name = _username;
    const openers = [
      "Hey{n}! How's your day going?",
      "Hi{n}! What have you been up to?",
      "Hey there{n}! Anything on your mind today?",
      "Hi{n}! How's everything?",
      "Hey{n}! What's been good lately?",
    ];
    final insertion = (name != null && name.isNotEmpty) ? " $name" : "";
    final opener = openers[Random().nextInt(openers.length)]
        .replaceFirst('{n}', insertion);

    return Scenario(
      id: 'freestyle_1',
      title: 'Freestyle Chat',
      systemPrompt: _withUserContext(
        "You are a warm, curious friend having a casual English conversation with the user. "
        "This is free-form small talk — their day, their life, their interests, whatever comes up. "
        "You are NOT a teacher and you do NOT correct them. Instead, silently model good English "
        "by naturally rephrasing their ideas with better grammar and phrasing in your own replies. "
        "Never say things like \"you should say X\" or \"the correct word is Y\".\n\n"
        "Style rules:\n"
        "- Keep replies short and natural: 1-2 sentences, usually under 20 words.\n"
        "- Ask a genuine follow-up question most turns to keep the chat flowing.\n"
        "- Match the user's energy. If they give a short answer, don't lecture.\n"
        "- If they go quiet or give very short replies, gently offer a new thread (\"By the way, how's your weekend looking?\").\n"
        "- Stay in English. No emojis, no asterisks, no stage directions.\n\n"
        "Ending rule:\n"
        "- After roughly 15-20 user turns, or if the conversation naturally winds down, warmly wrap up in 1 sentence and end your final message with the exact token [END_CONVERSATION].\n"
        "- If the user clearly wants to stop (\"bye\", \"I have to go\", \"that's it for today\"), wrap up and emit [END_CONVERSATION] immediately.",
      ),
      initialGreeting: opener,
    );
  }

  // --- Navigation -----------------------------------------------------------

  void _openScenario(Scenario scenario) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScenarioChatScreen(scenario: scenario),
      ),
    );
  }

  void _openTimedPresentation() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TimedPresentationScreen()),
    );
  }

  // --- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _softBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _primaryPurple),
        title: const Text(
          'Start a Conversation',
          style: TextStyle(
            color: _textDark,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroCard(),
              const SizedBox(height: 28),
              const SectionHeader(title: 'Timed Practice'),
              const SizedBox(height: 12),
              _buildTimedPresentationCard(),
              const SizedBox(height: 28),
              const SectionHeader(title: 'Role-play Scenarios', count: 5),
              const SizedBox(height: 12),
              _buildPracticeTile(
                icon: Icons.fastfood_outlined,
                title: 'Ordering Fast Food',
                subtitle: 'Practice ordering food at a drive-thru',
                onTap: () => _openScenario(_buildFastFoodScenario()),
              ),
              const SizedBox(height: 12),
              _buildPracticeTile(
                icon: Icons.work_outline,
                title: 'Job Interview',
                subtitle: 'Professional mock interview practice',
                onTap: () => _openScenario(_buildJobInterviewScenario()),
              ),
              const SizedBox(height: 12),
              _buildPracticeTile(
                icon: Icons.flight_takeoff_outlined,
                title: 'Travel & Hotel',
                subtitle: 'Check in and navigate hotel stays',
                onTap: () => _openScenario(_buildHotelScenario()),
              ),
              const SizedBox(height: 12),
              _buildPracticeTile(
                icon: Icons.medical_services_outlined,
                title: "Doctor's Visit",
                subtitle: 'Describe symptoms at a clinic appointment',
                onTap: () => _openScenario(_buildDoctorVisitScenario()),
              ),
              const SizedBox(height: 12),
              _buildPracticeTile(
                icon: Icons.headset_mic_outlined,
                title: 'Customer Service Call',
                subtitle: 'Resolve an issue over the phone',
                onTap: () => _openScenario(_buildCustomerServiceScenario()),
              ),
              const SizedBox(height: 28),
              const SectionHeader(title: 'Open Conversation'),
              const SizedBox(height: 12),
              _buildFreestyleCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF9F5FF), Color(0xFFF0E6FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEADCFF)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _primaryPurple.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.record_voice_over_rounded,
              color: _primaryPurple,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready to practice?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Pick a mode and we'll take it from there.",
                  style: TextStyle(
                    fontSize: 13,
                    color: _textGrey,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimedPresentationCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openTimedPresentation,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _primaryPurple.withOpacity(0.25)),
            boxShadow: [
              BoxShadow(
                color: _primaryPurple.withOpacity(0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _primaryPurple.withOpacity(0.18),
                      _primaryPurple.withOpacity(0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  color: _primaryPurple,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Timed Presentation',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Record a short monologue and get feedback',
                      style: TextStyle(
                        fontSize: 13,
                        color: _textGrey,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: _textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPracticeTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
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
                  color: _primaryPurple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: _primaryPurple, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: _textGrey,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: _textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFreestyleCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openScenario(_buildFreestyleScenario()),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _primaryPurple.withOpacity(0.08),
                _primaryPurple.withOpacity(0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _primaryPurple.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _primaryPurple.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.forum_outlined,
                  color: _primaryPurple,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Freestyle Chat',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Free-flowing small talk with your AI buddy',
                      style: TextStyle(
                        fontSize: 13,
                        color: _textGrey,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: _textGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
