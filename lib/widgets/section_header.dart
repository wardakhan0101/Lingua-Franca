import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A labelled section title used on home, practice hub, profile, and reports.
/// Optionally renders a count chip next to the title.
class SectionHeader extends StatelessWidget {
  final String title;
  final int? count;

  const SectionHeader({super.key, required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );

    if (count == null) return titleText;

    return Row(
      children: [
        titleText,
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}
