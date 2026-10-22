import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Avatar redondo sem nome ao lado: a foto, ou a inicial nas cores dadas.
/// Para quando o nome aparece noutro sítio (faixas e cartões do pedido
/// direto); com o nome ao lado usar [UserAvatarWithName].
class AppInitialsAvatar extends StatelessWidget {
  const AppInitialsAvatar({
    super.key,
    required this.initial,
    required this.radius,
    this.avatarUrl,
    this.background = AppColors.primaryContainer,
    this.foreground = AppColors.primary,
    this.textStyle,
  });

  final String initial;
  final double radius;

  /// Vazio ou `null` mostra a inicial.
  final String? avatarUrl;
  final Color background;
  final Color foreground;

  /// Estilo da inicial (cor e peso são sempre os do avatar).
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    final style = textStyle ?? Theme.of(context).textTheme.labelLarge;

    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      backgroundImage: hasPhoto ? NetworkImage(url) : null,
      child: hasPhoto
          ? null
          : Text(
              initial,
              style: style?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
