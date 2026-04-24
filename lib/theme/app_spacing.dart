/// 4pt spacing scale. Replaces the mix of 20/24/28/32 magic numbers sprinkled
/// through screen layouts. New code should use these constants for EdgeInsets
/// and SizedBox gaps.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  // Card corner radius — used in app_card, auth fields, dialogs.
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;
}
