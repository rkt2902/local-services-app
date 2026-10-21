import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

class UserAvatarWithName extends StatelessWidget {
  const UserAvatarWithName({
    super.key,
    required this.name,
    this.avatarUrl,
    this.radius = 20.0,
    this.nameStyle,
    this.fallbackLabel,
    this.subtitle,
  });

  /// Linha secundária por baixo do nome (ex.: "Corte de relva · 200 m²").
  final String? subtitle;

  final String name;
  final String? avatarUrl;
  final double radius;
  final TextStyle? nameStyle;

  /// Mostrado (e usado para a inicial do avatar) quando [name] vier vazio.
  /// Um nome vazio aqui normalmente significa que o perfil da contraparte
  /// ainda não está acessível (RLS antes de um relacionamento aceite, ou
  /// perfil sem `full_name`) — não que "esta pessoa não tem nome". Os
  /// ecrãs que mostram cliente/jardineiro devem passar "Cliente"/
  /// "Jardineiro" em vez de deixar o padrão "—", que parece um erro em vez
  /// de um género conhecido.
  final String? fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    final displayName = name.isNotEmpty ? name : (fallbackLabel ?? '—');
    final initialSource = name.isNotEmpty ? name : (fallbackLabel ?? '');
    final initial =
        initialSource.isNotEmpty ? initialSource.trim()[0].toUpperCase() : '?';

    return Row(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
          child: hasAvatar
              ? null
              : Text(
                  initial,
                  style: TextStyle(
                    fontSize: radius * 0.75,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.s10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayName,
                style: nameStyle ?? theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
