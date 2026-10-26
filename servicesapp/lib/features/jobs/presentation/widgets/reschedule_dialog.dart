import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../core/widgets/app_date_picker.dart';
import '../../../../core/widgets/app_time_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';

class RescheduleDialog extends StatefulWidget {
  const RescheduleDialog._();

  static Future<Map<String, dynamic>?> show(BuildContext context) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const RescheduleDialog._(),
    );
  }

  @override
  State<RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<RescheduleDialog> {
  DateTime? _date;
  TimeOfDay? _time;
  bool _flexible = false;

  Future<void> _pickDate() async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showAppTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  bool get _valid {
    if (_date == null) return false;
    if (!_flexible && _time == null) return false;
    return true;
  }

  void _confirm() {
    final timeStr = _time != null
        ? '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}'
        : null;
    Navigator.pop(context, {
      'date': _date!,
      'time': timeStr,
      'flexible': _flexible,
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dateText = _date == null
        ? 'Escolher data *'
        : DateFormat('dd/MM/yyyy').format(_date!);
    final timeText = _time == null
        ? 'Escolher hora *'
        : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}';

    return AppConfirmDialog(
      icon: Icons.event_repeat_outlined,
      title: 'Propor remarcação',
      message: 'Escolhe uma nova data e hora. A outra parte tem de aceitar.',
      confirmLabel: 'Enviar proposta',
      onCancel: () => Navigator.pop(context),
      onConfirm: _valid ? _confirm : null,
      details: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xs),
          _PickerButton(
            icon: Icons.calendar_today_outlined,
            label: dateText,
            onPressed: _pickDate,
          ),
          const SizedBox(height: AppSpacing.xs),
          SwitchListTile(
            title: Text(
              'Horário flexível neste dia',
              style: textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textPrimary),
            ),
            value: _flexible,
            onChanged: (v) => setState(() {
              _flexible = v;
              if (v) _time = null;
            }),
            contentPadding: EdgeInsets.zero,
          ),
          if (!_flexible) ...[
            const SizedBox(height: AppSpacing.xxs),
            _PickerButton(
              icon: Icons.access_time_outlined,
              label: timeText,
              onPressed: _pickTime,
            ),
          ],
        ],
      ),
    );
  }
}

/// Botão de escolher data/hora, com o rebordo e os cantos dos campos.
class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: AppSizes.inlineIcon),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSizes.compactButtonHeight),
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        textStyle: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
