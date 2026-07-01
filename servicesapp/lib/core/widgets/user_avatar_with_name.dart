import 'package:flutter/material.dart';

class UserAvatarWithName extends StatelessWidget {
  const UserAvatarWithName({
    super.key,
    required this.name,
    this.avatarUrl,
    this.radius = 20.0,
    this.nameStyle,
  });

  final String name;
  final String? avatarUrl;
  final double radius;
  final TextStyle? nameStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;
    final initial = name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';

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
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name.isNotEmpty ? name : '—',
            style: nameStyle ?? theme.textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
