import 'package:flutter/material.dart';

import '../constants/password_policy.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_color.dart';

/// Barra de força (fraca/média/boa) + lista das 3 regras com estado —
/// calcula tudo a partir de [password] via `password_policy.dart`, o único
/// sítio onde as regras vivem. Usado em `signup_screen.dart` e no ecrã de
/// nova password do fluxo de recuperação.
class AppPasswordStrengthMeter extends StatelessWidget {
  const AppPasswordStrengthMeter({super.key, required this.password});

  final String password;

  String _label(PasswordStrength s) => switch (s) {
        PasswordStrength.weak => 'Fraca',
        PasswordStrength.medium => 'Média',
        PasswordStrength.strong => 'Boa',
      };

  int _activeSegments(PasswordStrength s) => switch (s) {
        PasswordStrength.weak => 1,
        PasswordStrength.medium => 2,
        PasswordStrength.strong => 3,
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final result = evaluatePasswordPolicy(password);
    final activeSegments = _activeSegments(result.strength);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: List.generate(3, (i) {
                  final active = i < activeSegments;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i == 2 ? 0 : AppSpacing.xxs),
                      decoration: BoxDecoration(
                        color: active
                            ? AppStatusColor.success.foreground
                            : AppColors.divider,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              _label(result.strength),
              style: textTheme.labelMedium?.copyWith(
                color: AppStatusColor.success.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final rule in PasswordRule.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: _RequirementRow(
              label: rule.label,
              completed: result.isSatisfied(rule),
            ),
          ),
      ],
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.label, required this.completed});

  final String label;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = completed
        ? AppStatusColor.success.foreground
        : AppStatusColor.neutral.foreground;

    return Row(
      children: [
        Icon(
          completed ? Icons.check_circle_outline : Icons.circle_outlined,
          size: 18,
          color: color,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(label, style: textTheme.labelMedium?.copyWith(color: color)),
        ),
      ],
    );
  }
}
