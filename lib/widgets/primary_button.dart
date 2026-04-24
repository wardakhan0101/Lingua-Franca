import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Brand CTA button. The gradient variant is used for hero actions (home
/// "Start Conversation", timed presentation "View Analysis"). The flat variant
/// mirrors the achievement popup "Awesome!" button.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool gradient;
  final IconData? icon;
  final String? subtitle;
  final double height;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.gradient = false,
    this.icon,
    this.subtitle,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;

    final textColumn = subtitle == null
        ? Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );

    final row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 10),
        ],
        Flexible(child: textColumn),
      ],
    );

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            height: height,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            decoration: BoxDecoration(
              color: gradient ? null : AppColors.primary,
              gradient: gradient
                  ? const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryGradientEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              boxShadow: gradient
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: row,
          ),
        ),
      ),
    );
  }
}
