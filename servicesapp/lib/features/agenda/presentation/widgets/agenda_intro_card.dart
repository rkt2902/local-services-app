import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/primary_action_button.dart';

/// Cartão da primeira abertura da Agenda (A8G, P1 e P2): fica no topo da
/// lista e não tapa nada. O host decide quando aparece e guarda o fecho.
class AgendaIntroCard extends StatelessWidget {
  const AgendaIntroCard({
    required this.onDismiss,
    required this.onAddFirstWork,
    required this.onOpenColors,
    super.key,
  });

  /// ✕ e "Agora não".
  final VoidCallback onDismiss;

  /// "Adicionar o primeiro trabalho": abre o formulário (Trabalho, hoje).
  final VoidCallback onAddFirstWork;

  /// "O que significam as cores?": a mesma folha do botão "Cores".
  final VoidCallback onOpenColors;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget point(IconData icon, Color color, String label) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSizes.emphasisIcon, color: color),
          const SizedBox(width: AppSpacing.s10),
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.agendaAppBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'A tua agenda',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: onDismiss,
                tooltip: 'Fechar',
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                point(
                  Icons.event_available_outlined,
                  AppColors.primary,
                  'Os trabalhos da app aparecem aqui sozinhos',
                ),
                point(
                  Icons.edit_note_rounded,
                  AppColors.textSecondary,
                  'Junta os clientes que tens fora da app',
                ),
                point(
                  Icons.warning_rounded,
                  AppStatusColor.waiting.foreground,
                  'Avisamos se dois trabalhos coincidirem',
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryActionButton(
                  label: 'Adicionar o primeiro trabalho',
                  icon: Icons.add_rounded,
                  onPressed: onAddFirstWork,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: onDismiss,
                      child: const Text('Agora não'),
                    ),
                    TextButton.icon(
                      onPressed: onOpenColors,
                      icon: const Icon(
                        Icons.palette_outlined,
                        size: AppSizes.emphasisIcon,
                      ),
                      label: const Text('O que significam as cores?'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
