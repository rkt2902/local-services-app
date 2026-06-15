import 'package:flutter/material.dart';

import '../../data/cancel_reasons.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Cancelar pedido'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Indica a razão do cancelamento',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _selectedReason,
              onChanged: (v) => setState(() => _selectedReason = v),
              child: Column(
                children: _reasons
                    .map(
                      (reason) => RadioListTile<String>(
                        value: reason,
                        title: Text(CancelReason.label(reason)),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    )
                    .toList(),
              ),
            ),
            if (_selectedReason == CancelReason.other) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _detailController,
                maxLength: 200,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Descreve a razão (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Esta ação não pode ser desfeita.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: _selectedReason == null
              ? null
              : () => Navigator.pop(context, {
                    'reason': _selectedReason!,
                    'reasonDetail': _selectedReason == CancelReason.other
                        ? (_detailController.text.trim().isEmpty
                            ? null
                            : _detailController.text.trim())
                        : null,
                  }),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            disabledBackgroundColor:
                theme.colorScheme.error.withValues(alpha: 0.38),
          ),
          child: const Text('Confirmar cancelamento'),
        ),
      ],
    );
  }
}
