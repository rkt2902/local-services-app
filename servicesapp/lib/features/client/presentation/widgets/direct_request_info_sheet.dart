import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_sheet.dart';

/// Explicação do pedido direto na primeira utilização (design A5, 5), com
/// "Não voltar a mostrar". Quem abre decide quando mostrar e guarda a
/// preferência; a folha só fecha depois de [onConfirm] correr bem.
class DirectRequestInfoSheetViewData {
  const DirectRequestInfoSheetViewData({
    required this.titleLabel,
    required this.descriptionLabel,
    required this.confirmActionLabel,
    required this.hideAgainLabel,
  });

  final String titleLabel;
  final String descriptionLabel;
  final String confirmActionLabel;
  final String hideAgainLabel;
}

/// `true` quando o cliente confirma, `false`/`null` quando fecha.
/// [onConfirm] recebe a escolha "Não voltar a mostrar" e devolve `null` em
/// sucesso ou a mensagem de erro.
Future<bool?> showDirectRequestInfoSheet({
  required BuildContext context,
  required DirectRequestInfoSheetViewData data,
  required Future<String?> Function(bool doNotShowAgain) onConfirm,
}) {
  return AppSheet.show<bool>(
    context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _DirectRequestInfoSheetBody(data: data, onConfirm: onConfirm),
  );
}

class _DirectRequestInfoSheetBody extends StatefulWidget {
  const _DirectRequestInfoSheetBody({
    required this.data,
    required this.onConfirm,
  });

  final DirectRequestInfoSheetViewData data;
  final Future<String?> Function(bool doNotShowAgain) onConfirm;

  @override
  State<_DirectRequestInfoSheetBody> createState() =>
      _DirectRequestInfoSheetBodyState();
}

class _DirectRequestInfoSheetBodyState
    extends State<_DirectRequestInfoSheetBody> {
  bool _doNotShowAgain = false;
  bool _submitting = false;
  String? _error;

  Future<void> _confirm() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onConfirm(_doNotShowAgain);
    } catch (_) {
      error = 'Não foi possível guardar esta preferência. Tenta novamente.';
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  void _toggle(bool? value) {
    if (_submitting) return;
    setState(() => _doNotShowAgain = value ?? !_doNotShowAgain);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const tone = AppStatusColor.info;

    return AppSheet(
      title: widget.data.titleLabel,
      primaryActionLabel: widget.data.confirmActionLabel,
      onPrimaryAction: _confirm,
      isSubmitting: _submitting,
      onClose: () => Navigator.of(context).pop(false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tone.background,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: tone.foreground),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.data.descriptionLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          InkWell(
            onTap: _submitting ? null : () => _toggle(null),
            borderRadius: BorderRadius.circular(AppRadius.input),
            child: Row(
              children: [
                Checkbox(
                  value: _doNotShowAgain,
                  onChanged: _submitting ? null : _toggle,
                  activeColor: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    widget.data.hideAgainLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    );
  }
}
