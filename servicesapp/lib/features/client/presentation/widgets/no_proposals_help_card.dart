import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_motion.dart';

/// Cartão "Ainda sem propostas" (RC5, 0062) no detalhe de um pedido aberto
/// do cliente, depois de 24h sem respostas. Sugere alargar a data, ajustar
/// a descrição (os dois abrem "Editar pedido") e mostrar o pedido mais
/// longe. Só apresentação: os textos vêm de `noProposalsHelpTexts`.
class NoProposalsHelpCardViewData {
  const NoProposalsHelpCardViewData({
    required this.titleLabel,
    required this.descriptionLabel,
    required this.dateActionLabel,
    required this.descriptionActionLabel,
    this.widenActionLabel,
  });

  final String titleLabel;
  final String descriptionLabel;
  final String dateActionLabel;
  final String descriptionActionLabel;

  /// `null` esconde o botão (o pedido já está no máximo).
  final String? widenActionLabel;
}

class NoProposalsHelpCard extends StatefulWidget {
  const NoProposalsHelpCard({
    super.key,
    required this.data,
    required this.onEditRequest,
    required this.onWiden,
  });

  final NoProposalsHelpCardViewData data;

  /// "Alargar a data" e "Ajustar a descrição".
  final VoidCallback? onEditRequest;

  /// Mostra o pedido mais longe. Devolve `null` em sucesso (o ecrã recarrega
  /// o pedido) ou a mensagem de erro, que fica dentro do cartão.
  final Future<String?> Function() onWiden;

  @override
  State<NoProposalsHelpCard> createState() => _NoProposalsHelpCardState();
}

class _NoProposalsHelpCardState extends State<NoProposalsHelpCard> {
  bool _submitting = false;
  String? _error;

  @override
  void didUpdateWidget(covariant NoProposalsHelpCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.widenActionLabel != widget.data.widenActionLabel ||
        oldWidget.data.descriptionLabel != widget.data.descriptionLabel) {
      _submitting = false;
      _error = null;
    }
  }

  Future<void> _widen() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onWiden();
    } catch (_) {
      error = 'Não foi possível mostrar o pedido mais longe. Tenta novamente.';
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const tone = AppStatusColor.waiting;
    final data = widget.data;
    final widenLabel = data.widenActionLabel;
    final onEdit = _submitting ? null : widget.onEditRequest;

    return AppStaggeredEntrance(
      index: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.travel_explore_rounded, color: tone.foreground),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.titleLabel,
                        style: textTheme.bodyMedium?.copyWith(
                          color: tone.foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        data.descriptionLabel,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _CardButton(
                    label: data.dateActionLabel,
                    icon: Icons.edit_calendar_outlined,
                    onPressed: onEdit,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _CardButton(
                    label: data.descriptionActionLabel,
                    icon: Icons.edit_note_rounded,
                    onPressed: onEdit,
                  ),
                ),
              ],
            ),
            if (widenLabel != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _CardButton(
                label: _submitting ? 'A mostrar mais longe...' : widenLabel,
                icon: Icons.near_me_outlined,
                onPressed: _submitting ? null : _widen,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _error!,
                style: textTheme.labelMedium?.copyWith(
                  color: AppStatusColor.cancelled.foreground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = onPressed == null
        ? AppStatusColor.neutral.foreground
        : AppColors.primary;
    return SizedBox(
      width: double.infinity,
      height: AppSizes.linkButtonHeight,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          disabledBackgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.divider),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
        ),
        icon: Icon(icon, size: AppSizes.inlineIcon, color: color),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
