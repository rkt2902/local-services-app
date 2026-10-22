import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_sheet.dart';
import 'work_photos_strip.dart';

/// Folha "Terminou o trabalho?" (design 7b), antes de `mark_job_done`.
/// Fotos de "depois" recomendadas (até 3), tempo registado e valor.
/// [onSend] faz o upload e chama a RPC; devolve `true` só depois de a BD
/// confirmar, e aí a folha fecha com `true`. "Continuar a trabalhar" fecha
/// com `false`.
class MarkCompletedSheet extends StatefulWidget {
  const MarkCompletedSheet({
    super.key,
    required this.clientName,
    required this.workedTimeLabel,
    required this.priceLabel,
    required this.onSend,
    this.workDaysLabel,
    this.fixedValue = false,
  });

  final String clientName;
  final String workedTimeLabel;
  final String priceLabel;
  final Future<bool> Function(List<XFile> photos) onSend;

  /// "3" quando o trabalho correu em vários dias (design A6, G).
  final String? workDaysLabel;

  /// Valor total fechado: o tempo fica registado mas não muda o valor.
  final bool fixedValue;

  static Future<bool> show(
    BuildContext context, {
    required String clientName,
    required String workedTimeLabel,
    required String priceLabel,
    required Future<bool> Function(List<XFile> photos) onSend,
    String? workDaysLabel,
    bool fixedValue = false,
  }) async {
    final sent = await AppSheet.show<bool>(
      context,
      builder: (_) => MarkCompletedSheet(
        clientName: clientName,
        workedTimeLabel: workedTimeLabel,
        priceLabel: priceLabel,
        onSend: onSend,
        workDaysLabel: workDaysLabel,
        fixedValue: fixedValue,
      ),
    );
    return sent ?? false;
  }

  @override
  State<MarkCompletedSheet> createState() => _MarkCompletedSheetState();
}

class _MarkCompletedSheetState extends State<MarkCompletedSheet> {
  List<XFile> _photos = const [];
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    final ok = await widget.onSend(_photos);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = widget.clientName.trim();
    final who = name.isEmpty ? 'ao cliente' : 'a $name';

    return AppSheet(
      title: 'Terminou o trabalho?',
      isSubmitting: _sending,
      onClose: () => Navigator.of(context).pop(false),
      primaryActionLabel: 'Enviar para confirmação',
      primaryActionIcon: Icons.send_rounded,
      onPrimaryAction: _send,
      secondaryActionLabel: 'Continuar a trabalhar',
      onSecondaryAction: () => Navigator.of(context).pop(false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Vamos pedir $who que confirme. O trabalho fica concluído quando '
            'confirmar, ou sozinho ao fim de 48 horas.',
            style:
                textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text.rich(
            TextSpan(
              text: 'Fotos do "depois"',
              style:
                  textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
              children: [
                TextSpan(
                  text: ' · recomendado',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          WorkPhotosStrip(
            photos: _photos,
            enabled: !_sending,
            onChanged: (photos) => setState(() => _photos = photos),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              children: [
                if (widget.workDaysLabel != null) ...[
                  _SummaryRow(
                    label: 'Dias de trabalho',
                    value: widget.workDaysLabel!,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                _SummaryRow(
                  label: 'Tempo registado',
                  value: widget.workedTimeLabel,
                ),
                const SizedBox(height: AppSpacing.xs),
                _SummaryRow(
                  label: widget.fixedValue ? 'Valor fechado' : 'Valor acordado',
                  value: widget.priceLabel,
                  highlighted: true,
                ),
                if (widget.fixedValue) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'O tempo fica registado, mas não muda o valor.',
                    style: textTheme.labelSmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: textTheme.bodyMedium?.copyWith(
              color: highlighted ? AppColors.primary : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
