import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_theme.dart';

/// One supported app's launcher icon, at the size every list uses.
///
/// The artwork comes from the device (see `candidateApps()` in the native
/// host), so the icon here is always the one on the user's home screen - they
/// recognise the app before they read the label, which is the whole point of
/// an icon.
///
/// The fallback is deliberate and boring: a rounded, brand-tinted square with
/// the app's initial. A missing icon (test harness, web preview, a drawable the
/// launcher itself could not render) must not change the height of a row or
/// leave a hole where a picture should be.
class AppIconTile extends StatelessWidget {
  const AppIconTile({
    required this.label,
    this.icon,
    this.size = 40,
    super.key,
  });

  final String label;
  final Uint8List? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(size * 0.28);
    final bytes = icon;

    if (bytes == null || bytes.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: AppTheme.brand.withValues(alpha: isDark ? 0.18 : 0.10),
          border: Border.all(
            color: AppTheme.brand.withValues(alpha: isDark ? 0.28 : 0.16),
          ),
        ),
        child: Text(
          _initial(label),
          style: theme.textTheme.titleSmall?.copyWith(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
            color: isDark ? AppTheme.brandBright : AppTheme.brand,
          ),
        ),
      );
    }

    // Decoded once per row rather than on every rebuild: these bytes do not
    // change for the life of the session.
    return ClipRRect(
      borderRadius: radius,
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        // A corrupt icon degrades to the same placeholder the null case uses,
        // instead of a red error box in the middle of the app list.
        errorBuilder: (context, _, _) =>
            AppIconTile(label: label, size: size, icon: null),
      ),
    );
  }

  static String _initial(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }
}
