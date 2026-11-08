import 'package:flutter/material.dart';

/// Centralized design tokens: one brand blue, one spacing scale, one corner
/// radius, one gradient. Screens never hard-code a colour or a margin; they
/// take them from here so light and dark stay in step with the mascot artwork
/// (design/app_redesign_preview.html is the reference).
class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------- colour

  /// The brand blue: the same blue the 3D bubble artwork is drawn on, so the
  /// character never sits on a foreign background.
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

  /// A screen background: brand glow at the top, night below.
  static LinearGradient backgroundGradient(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0A1120), Color(0xFF05080F)],
      );
    }
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFF2F6FF), Color(0xFFFBFCFF)],
    );
  }

  // --------------------------------------------------------------- spacing

  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  // ---------------------------------------------------------------- shapes

  static const double cardRadius = 18;
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
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? ink : const Color(0xFFF7F9FF),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
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
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: brand,
          foregroundColor: Colors.white,
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
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.9),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.09)
                : scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        color: isDark ? Colors.white.withValues(alpha: 0.045) : Colors.white,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : scheme.outlineVariant.withValues(alpha: 0.7),
        ),
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? inkElevated : const Color(0xFF15203A),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Small, repeated visual pieces that are not worth their own widget file.
class AppSurfaces {
  AppSurfaces._();

  /// A brand-tinted pill, used for the saved reply style.
  static Widget pill(
    BuildContext context, {
    required Widget child,
    bool accent = false,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: child,
    );
    return Material(
      color: accent
          ? AppTheme.brand.withValues(alpha: isDark ? 0.22 : 0.12)
          : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(
          color: accent
              ? AppTheme.brandBright.withValues(alpha: 0.42)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: content,
      ),
    );
  }
}
