import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = _date == null
        ? 'Escolher data *'
        : DateFormat('dd/MM/yyyy').format(_date!);
    final timeText =
        _time == null ? 'Escolher hora *' : _time!.format(context);

    return AlertDialog(
      title: const Text('Propor remarcação'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Escolhe uma nova data e hora',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(dateText),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Horário flexível neste dia'),
              value: _flexible,
              onChanged: (v) => setState(() {
                _flexible = v;
                if (v) _time = null;
              }),
              contentPadding: EdgeInsets.zero,
            ),
            if (!_flexible) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.access_time_outlined),
                label: Text(timeText),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton(
          onPressed: _valid
              ? () {
                  final timeStr = _time != null
                      ? '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}'
                      : null;
                  Navigator.pop(context, {
                    'date': _date!,
                    'time': timeStr,
                    'flexible': _flexible,
                  });
                }
              : null,
          child: const Text('Enviar proposta de remarcação'),
        ),
      ],
    );
  }
}
