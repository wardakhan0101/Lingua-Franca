import 'package:flutter/material.dart';

// Metadata for a single achievement badge. Previously duplicated inside
// `BadgesScreen`; extracted so the achievement popup can render the same
// icon/color/description without a second source of truth.
class BadgeModel {
  final String name;
  final String description;
  final IconData icon;
  final Color color;

  const BadgeModel({
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
  });
}

// The full catalogue of badges the gamification service knows how to award.
// Keep this list in sync with the award conditions in
// `lib/services/gamification_service.dart :: _checkAndAwardBadges` — names
// must match exactly, or the popup won't find the badge.
const List<BadgeModel> kAllBadges = [
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
    name: 'Intermediate Master',
    description: 'Reach the Intermediate level.',
    icon: Icons.military_tech,
    color: Colors.deepOrange,
  ),
  BadgeModel(
    name: 'Clear Speaker',
    description: 'Score 80% or higher on pronunciation in your first session.',
    icon: Icons.record_voice_over,
    color: Colors.green,
  ),
  BadgeModel(
    name: 'Phoneme Master',
    description: 'Complete 10 sessions with at least 85% pronunciation.',
    icon: Icons.stars,
    color: Colors.purple,
  ),
  BadgeModel(
    name: 'TH Conqueror',
    description: 'Correctly produce the /θ/ or /ð/ sound 20 times across sessions.',
    icon: Icons.emoji_events,
    color: Colors.orange,
  ),
  BadgeModel(
    name: 'Accent Warrior',
    description: 'Improve your average pronunciation score by 15+ points.',
    icon: Icons.trending_up,
    color: Colors.teal,
  ),
];

// Case-sensitive lookup by badge name. Returns null for unknown names so
// callers can skip defensively (e.g., if Firestore carries a legacy badge
// name that isn't in this catalogue).
BadgeModel? badgeByName(String name) {
  for (final b in kAllBadges) {
    if (b.name == name) return b;
  }
  return null;
}
