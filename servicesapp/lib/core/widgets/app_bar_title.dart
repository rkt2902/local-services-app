import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Título de AppBar com uma segunda linha opcional, mais pequena.
/// Ex.: "Poda" por cima de "Braga · 18/10".
class AppBarTitle extends StatelessWidget {
  const AppBarTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
    );
    final sub = subtitle;
    if (sub == null || sub.isEmpty) return titleText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        titleText,
        Text(
          sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
