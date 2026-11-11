import 'package:flutter/material.dart';

/// Centralized design tokens: one brand blue, one spacing scale, one corner
/// radius family and one gradient. Screens take their visual language from
/// here so light and dark stay in step with the mascot artwork.
class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------- colour

  /// The brand blue: the same blue family as the 3D bubble artwork.
  static const Color seed = Color(0xFF1B6EF3);
  static const Color brand = seed;
  static const Color brandBright = Color(0xFF4A94FF);
  static const Color cyan = Color(0xFF38D9F8);

  /// State colours. `mint` = good, `amber` = needs attention, `danger` = wrong.
  static const Color mint = Color(0xFF43E0A0);
  static const Color amber = Color(0xFFFFB545);
  static const Color danger = Color(0xFFFF5D6C);

  /// The night surfaces the app is designed on.
  static const Color ink = Color(0xFF070B14);
  static const Color inkSurface = Color(0xFF0C1220);
  static const Color inkElevated = Color(0xFF131B2C);

  /// The mascot disc: highlight -> base, top-left to bottom-right.
  static const Color mascotHighlight = Color(0xFF4A94FF);
  static const Color mascotBase = Color(0xFF114FD0);

  /// The one gradient the app uses for anything primary.
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand, brandBright, cyan],
  );

  /// A quiet screen background: cool light surfaces, deep navy at night.
  static LinearGradient backgroundGradient(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0B1425), Color(0xFF05080F)],
      );
    }
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFF0F5FF), Color(0xFFFAFCFF)],
    );
  }

  // --------------------------------------------------------------- spacing

  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  /// Phones use the full available width; tablets keep a readable measure
  /// instead of stretching cards and copy from edge to edge.
  static const double contentMaxWidth = 680;

  // ---------------------------------------------------------------- shapes

  static const double cardRadius = 20;
  static const double tileRadius = 16;
  static const double buttonRadius = 16;

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness)
        .copyWith(
          primary: isDark ? brandBright : brand,
          secondary: cyan,
          surface: isDark ? inkSurface : Colors.white,
          surfaceContainerHighest: isDark
              ? inkElevated
              : const Color(0xFFEAF0FA),
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? ink : const Color(0xFFF7F9FF),
    );

    final borderRadius = BorderRadius.circular(14);
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          height: 1.15,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          height: 1.2,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
          height: 1.25,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          fontSize: 12.5,
          height: 1.45,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          backgroundColor: isDark
              ? Colors.white.withValues(alpha: 0.025)
              : Colors.white.withValues(alpha: 0.65),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.9),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? brandBright : brand,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.085)
                : scheme.outlineVariant.withValues(alpha: 0.62),
          ),
        ),
        color: isDark
            ? Colors.white.withValues(alpha: 0.045)
            : Colors.white.withValues(alpha: 0.94),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.11)
              : scheme.outlineVariant.withValues(alpha: 0.75),
        ),
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white,
        selectedColor: brand.withValues(alpha: isDark ? 0.25 : 0.12),
        checkmarkColor: isDark ? brandBright : brand,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceMd,
          vertical: AppTheme.spaceXs,
        ),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.black.withValues(alpha: 0.22)
            : const Color(0xFFF3F6FC),
        contentPadding: const EdgeInsets.all(14),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(
            color: isDark ? brandBright : brand,
            width: 1.4,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: isDark
            ? inkSurface.withValues(alpha: 0.98)
            : Colors.white.withValues(alpha: 0.98),
        surfaceTintColor: Colors.transparent,
        indicatorColor: brand.withValues(alpha: isDark ? 0.22 : 0.11),
        labelTextStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
          return IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? (isDark ? brandBright : brand)
                : scheme.onSurfaceVariant,
          );
        }),
      ),
      dividerTheme: DividerThemeData(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : scheme.outlineVariant.withValues(alpha: 0.72),
        thickness: 1,
        space: 1,
        indent: 16,
        endIndent: 16,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? inkElevated : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? inkElevated : const Color(0xFF15203A),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: brandBright,
      ),
    );
  }
}

/// Small, repeated visual pieces that are not worth their own widget file.
class AppSurfaces {
  AppSurfaces._();

  /// A readable content column on tablets and a full-width one on phones.
  static Widget centered(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppTheme.contentMaxWidth),
        child: child,
      ),
    );
  }

  /// The icon container used by feature rows and section headers.
  static Widget iconBadge(
    BuildContext context, {
    required IconData icon,
    Color? color,
    double size = 40,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground =
        color ?? (isDark ? AppTheme.brandBright : AppTheme.brand);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        color: foreground.withValues(alpha: isDark ? 0.16 : 0.10),
        border: Border.all(color: foreground.withValues(alpha: 0.10)),
      ),
      child: Icon(icon, size: size * 0.48, color: foreground),
    );
  }

  /// The single strong action treatment. Disabled actions lose the glow and
  /// gradient too, so the button never looks tappable when it is not.
  static Widget primaryAction(
    BuildContext context, {
    required String label,
    required VoidCallback? onPressed,
    Widget? icon,
  }) {
    final enabled = onPressed != null;
    final scheme = Theme.of(context).colorScheme;
    final buttonStyle = FilledButton.styleFrom(
      backgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      disabledBackgroundColor: Colors.transparent,
      disabledForegroundColor: scheme.onSurfaceVariant,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
        color: enabled ? null : scheme.surfaceContainerHighest,
        gradient: enabled ? AppTheme.primaryGradient : null,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppTheme.brand.withValues(alpha: 0.32),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: icon == null
          ? FilledButton(
              onPressed: onPressed,
              style: buttonStyle,
              child: Text(label),
            )
          : FilledButton.icon(
              onPressed: onPressed,
              icon: icon,
              label: Text(label),
              style: buttonStyle,
            ),
    );
  }

  /// A brand-tinted pill, used for values the app has already decided.
  static Widget pill(
    BuildContext context, {
    required Widget child,
    bool accent = false,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: child,
    );
    return Material(
      color: accent
          ? AppTheme.brand.withValues(alpha: isDark ? 0.22 : 0.10)
          : (isDark
                ? Colors.white.withValues(alpha: 0.055)
                : const Color(0xFFF7F9FD)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(
          color: accent
              ? AppTheme.brandBright.withValues(alpha: 0.32)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.09)
                    : Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
