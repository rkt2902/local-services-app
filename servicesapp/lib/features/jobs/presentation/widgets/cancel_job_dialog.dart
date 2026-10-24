import 'package:flutter/material.dart';

import '../../data/cancel_reasons.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../core/widgets/app_text_field.dart';

class CancelJobDialog extends StatefulWidget {
  const CancelJobDialog._({required this.isClient});

  final bool isClient;

  static Future<Map<String, String?>?> show(
    BuildContext context, {
    required bool isClient,
  }) {
    return showDialog<Map<String, String?>>(
      context: context,
      builder: (_) => CancelJobDialog._(isClient: isClient),
    );
  }

  @override
  State<CancelJobDialog> createState() => _CancelJobDialogState();
}

class _CancelJobDialogState extends State<CancelJobDialog> {
  String? _selectedReason;
  final _detailController = TextEditingController();

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  List<String> get _reasons => [
        CancelReason.personalIssue,
        CancelReason.scheduleConflict,
        if (widget.isClient) CancelReason.noLongerNeeded,
        CancelReason.other,
      ];

  void _confirm() {
    final detail = _detailController.text.trim();
    Navigator.pop(context, {
      'reason': _selectedReason!,
      'reasonDetail': _selectedReason == CancelReason.other && detail.isNotEmpty
          ? detail
          : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppConfirmDialog(
      icon: Icons.event_busy_outlined,
      title: 'Cancelar pedido',
      message: 'Indica a razão do cancelamento.',
      destructive: true,
      confirmLabel: 'Cancelar pedido',
      onCancel: () => Navigator.pop(context),
      onConfirm: _selectedReason == null ? null : _confirm,
      details: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioGroup<String>(
            groupValue: _selectedReason,
            onChanged: (v) => setState(() => _selectedReason = v),
            child: Column(
              children: _reasons
                  .map(
                    (reason) => RadioListTile<String>(
                      value: reason,
                      title: Text(
                        CancelReason.label(reason),
                        style: textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textPrimary),
                      ),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  )
                  .toList(),
            ),
          ),
          if (_selectedReason == CancelReason.other) ...[
            const SizedBox(height: AppSpacing.xs),
            AppTextField(
              controller: _detailController,
              label: 'Descreve a razão (opcional)',
              maxLength: 200,
              minLines: 2,
              maxLines: 3,
              textInputAction: TextInputAction.newline,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Esta ação não pode ser desfeita.',
            style: textTheme.labelMedium
                ?.copyWith(color: AppStatusColor.cancelled.foreground),
          ),
        ],
      ),
    );
  }
}
