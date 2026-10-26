import 'package:flutter/material.dart';

import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../core/widgets/app_text_field.dart';

/// "Reportar problema" num trabalho em curso: devolve a descrição (10+
/// caracteres) ou `null` se fechar. Não chama o backend.
class ReportProblemDialog extends StatefulWidget {
  const ReportProblemDialog._();

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const ReportProblemDialog._(),
    );
  }

  @override
  State<ReportProblemDialog> createState() => _ReportProblemDialogState();
}

class _ReportProblemDialogState extends State<ReportProblemDialog> {
  static const _minLength = 10;

  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppConfirmDialog(
      icon: Icons.report_problem_outlined,
      title: 'Reportar problema',
      message: 'Conta-nos o que aconteceu. A nossa equipa vai analisar.',
      confirmLabel: 'Enviar',
      onCancel: () => Navigator.pop(context),
      onConfirm: _submit,
      details: Form(
        key: _formKey,
        child: AppTextField(
          controller: _controller,
          label: 'Descreve o que aconteceu',
          minLines: 3,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          validator: (v) => (v == null || v.trim().length < _minLength)
              ? 'Descreve o problema (mínimo $_minLength caracteres).'
              : null,
        ),
      ),
    );
  }
}
