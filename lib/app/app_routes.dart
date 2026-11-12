/// Named routes, shared with the native layer.
/// [overlay] is also the value of `OverlayPanelActivity.getInitialRoute()` in
/// Kotlin: the panel activity is a separate Flutter launch, and this string is
/// the seam between it and [AppRoutes]. Change one, change both.
class AppRoutes {
  AppRoutes._();

  /// The normal boot route: onboarding or home.
  static const String home = '/';

  /// The floating reply panel. Never pushed by
  /// in-app navigation - only ever the initial route of the panel activity.
  static const String overlay = '/overlay';
}
