import 'package:flutter/material.dart';

class BadgeModel {
  final String name;
  final String description;
  final IconData icon;
  final Color color;

  BadgeModel({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class BadgesScreen extends StatelessWidget {
  final List<String> unlockedBadges;

  BadgesScreen({super.key, required this.unlockedBadges});

  final List<BadgeModel> allBadges = [
    BadgeModel(
      name: 'Iron Lung',
      description: 'Complete a speaking session longer than 3 minutes.',
      icon: Icons.air,
      color: Colors.blue,
    ),
    BadgeModel(
      name: 'Grammar Wizard',
      description: 'Complete a perfect session with zero grammar mistakes.',
      icon: Icons.auto_fix_high,
      color: Colors.purple,
    ),
    BadgeModel(
      name: 'Night Owl',
      description: 'Practice late at night (between 11 PM and 5 AM).',
      icon: Icons.nightlight_round,
      color: Colors.indigo,
    ),
    BadgeModel(
      name: 'Early Bird',
      description: 'Start your day with practice (between 5 AM and 9 AM).',
      icon: Icons.wb_sunny,
      color: Colors.orange,
    ),
    BadgeModel(
      name: 'Streak Starter',
      description: 'Maintain a practice streak for 3 consecutive days.',
      icon: Icons.bolt,
      color: Colors.amber,
    ),
    BadgeModel(
      name: 'Weekly Warrior',
      description: 'Demonstrate dedication with a 7-day practice streak.',
      icon: Icons.workspace_premium,
      color: Colors.redAccent,
    ),
    BadgeModel(
      name: 'Persistent Learner',
      description: 'Complete 10 total practice sessions.',
      icon: Icons.menu_book,
      color: Colors.green,
    ),
    BadgeModel(
      name: 'B2 Master',
      description: 'Reach the B2 Upper Intermediate level.',
      icon: Icons.military_tech,
      color: Colors.deepOrange,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FA),
      appBar: AppBar(
        title: const Text(
          'All Achievements',
          style: TextStyle(color: Color(0xFF101828), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF101828)),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: allBadges.length,
        itemBuilder: (context, index) {
          final badge = allBadges[index];
          final bool isUnlocked = unlockedBadges.contains(badge.name);

          return _buildBadgeCard(badge, isUnlocked);
        },
      ),
    );
  }

  Widget _buildBadgeCard(BadgeModel badge, bool isUnlocked) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isUnlocked ? badge.color.withOpacity(0.1) : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              badge.icon,
              size: 40,
              color: isUnlocked ? badge.color : Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            badge.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isUnlocked ? const Color(0xFF101828) : Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              badge.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isUnlocked ? const Color(0xFF667085) : Colors.grey.shade300,
              ),
            ),
          ),
          if (!isUnlocked)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade300),
            ),
        ],
      ),
    );
  }
}
