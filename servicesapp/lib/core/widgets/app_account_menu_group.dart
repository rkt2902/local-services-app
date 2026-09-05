import 'package:flutter/material.dart';

import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/core/theme/app_radius.dart';
import 'package:servicesapp/core/theme/app_spacing.dart';

class AppAccountMenuItem {
  const AppAccountMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    this.trailingLabel,
  });

  final String id;
  final String label;
  final IconData icon;
  final String? trailingLabel;
}

class AppAccountMenuGroup extends StatelessWidget {
  const AppAccountMenuGroup({
    required this.items,
    required this.onItemPressed,
    super.key,
  });

  final List<AppAccountMenuItem> items;
  final ValueChanged<String> onItemPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(
          AppRadius.card,
        ),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _AccountMenuRow(
              item: items[index],
              onPressed: () {
                onItemPressed(items[index].id);
              },
            ),
            if (index < items.length - 1)
              const Divider(
                height: 1,
                color: AppColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _AccountMenuRow extends StatelessWidget {
  const _AccountMenuRow({
    required this.item,
    required this.onPressed,
  });

  final AppAccountMenuItem item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(
          AppRadius.input,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: 56,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 21,
                  color: AppColors.primary,
                ),
                const SizedBox(
                  width: AppSpacing.sm,
                ),
                Expanded(
                  child: Text(
                    item.label,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (item.trailingLabel != null) ...[
                  const SizedBox(
                    width: AppSpacing.sm,
                  ),
                  Text(
                    item.trailingLabel!,
                    style: textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(
                  width: AppSpacing.xs,
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
