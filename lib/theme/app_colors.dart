import 'package:flutter/material.dart';

/// Single source of truth for brand colors. Replaces the 5 hardcoded purple
/// variants (#6B72AB, #8A48F0, #6C63FF, #7630E1, #6332D1) that were scattered
/// across screens. New code should import `AppColors` — do not introduce
/// new hex literals for brand surfaces.
class AppColors {
  AppColors._();

  // Brand purple — the one actually used on home, practice hub, chat, popup.
  static const Color primary = Color(0xFF8A48F0);
  static const Color primaryDark = Color(0xFF6332D1);
  static const Color primaryLight = Color(0xFFD9BFFF);

  // Gradient companion for hero CTAs (home "Start Conversation" button).
  static const Color primaryGradientEnd = Color(0xFFA372F4);

  // Neutrals.
  static const Color background = Color(0xFFF7F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF101828);
  static const Color textSecondary = Color(0xFF667085);
  static Color get border => Colors.grey.shade100;

  // Semantic.
  static const Color success = Color(0xFF12B76A);
  static const Color warning = Color(0xFFF79009);
  static const Color danger = Color(0xFFD92D20);
  static const Color dangerSoft = Color(0xFFFEE4E2);

  // Gamification accents.
  static const Color xp = Color(0xFFFF9900);
  static const Color streak = Color(0xFFFF512F);
  static const Color gold = Color(0xFFD4AF37);

  // Chat-specific gradient end (darker purple used only in scenario bubbles).
  static const Color chatBubbleEnd = primaryDark;
}
