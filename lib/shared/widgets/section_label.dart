import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// The small uppercase-free section heading used above every control group
/// ("Output language", "Tone", "Selected apps").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
