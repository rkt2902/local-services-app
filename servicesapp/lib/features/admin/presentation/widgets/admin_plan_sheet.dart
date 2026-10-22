import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/widgets/app_date_picker.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_sheet.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../application/admin_labels.dart';
import '../../application/admin_providers.dart';
import '../../data/admin_models.dart';

/// Folha para atribuir o plano. Devolve `true` depois de a BD gravar.
Future<bool?> showAdminPlanSheet(
  BuildContext context, {
  required AdminWorkerDetail worker,
}) {
  return AppSheet.show<bool>(
    context,
    builder: (_) => _AdminPlanSheet(worker: worker),
  );
}

/// Durações rápidas para a data de fim: (rótulo, meses).
const _durations = <(String, int)>[
  ('1 mês', 1),
  ('3 meses', 3),
  ('12 meses', 12),
];

class _AdminPlanSheet extends ConsumerStatefulWidget {
  const _AdminPlanSheet({required this.worker});

  final AdminWorkerDetail worker;

  @override
  ConsumerState<_AdminPlanSheet> createState() => _AdminPlanSheetState();
}

class _AdminPlanSheetState extends ConsumerState<_AdminPlanSheet> {
  late WorkerPlanTier _tier;
  late DateTime _startsAt;
  DateTime? _endsAt;
  late bool _verified;
  DateTime? _verifiedAt;
  late final TextEditingController _notesController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final plan = widget.worker.plan;
    final today = DateUtils.dateOnly(DateTime.now());
    _tier = plan.tier ?? WorkerPlanTier.free;
    _startsAt = plan.startsAt ?? today;
    _endsAt = plan.endsAt;
    _verifiedAt = plan.verifiedAt;
    _verified = plan.verifiedAt != null;
    _notesController = TextEditingController(text: plan.notes ?? '');
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  DateTime _addMonths(DateTime from, int months) =>
      DateTime(from.year, from.month + months, from.day);

  Future<void> _pickDate({required bool end}) async {
    final initial = end ? (_endsAt ?? _addMonths(_startsAt, 12)) : _startsAt;
    final picked = await showAppDatePicker(
      context: context,
      initialDate: initial,
      firstDate: end ? _startsAt : DateTime(2025),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (end) {
        _endsAt = picked;
      } else {
        _startsAt = picked;
        final endsAt = _endsAt;
        if (endsAt != null && endsAt.isBefore(picked)) _endsAt = null;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final paid = _tier.isPaid;
    try {
      await ref.read(adminRepositoryProvider).setWorkerPlan(
            workerId: widget.worker.workerId,
            tier: _tier,
            startsAt: _startsAt,
            endsAt: paid ? _endsAt : null,
            verifiedAt: _verified
                ? (_verifiedAt ?? DateUtils.dateOnly(DateTime.now()))
                : null,
            notes: _notesController.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary =
        textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);
    final paid = _tier.isPaid;
    final error = _error;

    return AppSheet(
      title: 'Plano de ${widget.worker.fullName}',
      onClose: () => Navigator.of(context).pop(),
      primaryActionLabel: 'Guardar',
      onPrimaryAction: _saving ? null : _save,
      isSubmitting: _saving,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final tier in WorkerPlanTier.values)
                AppFilterChip(
                  label: tier.label,
                  selected: _tier == tier,
                  onPressed: () => setState(() => _tier = tier),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            paid
                ? 'Trabalhos sem limite e selo ${_tier.label}. Acaba sozinho '
                    'na data de fim e volta ao Grátis.'
                : 'Até 5 trabalhos aceites por mês.',
            style: secondary,
          ),
          if (paid) ...[
            const SizedBox(height: AppSpacing.md),
            _DateRow(
              label: 'Início',
              value: adminDateLabel(_startsAt),
              onPressed: () => _pickDate(end: false),
            ),
            _DateRow(
              label: 'Fim',
              value: _endsAt == null ? 'Sem fim' : adminDateLabel(_endsAt),
              onPressed: () => _pickDate(end: true),
            ),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final (label, months) in _durations)
                  AppFilterChip(
                    label: label,
                    onPressed: () => setState(
                        () => _endsAt = _addMonths(_startsAt, months)),
                  ),
                AppFilterChip(
                  label: 'Sem fim',
                  selected: _endsAt == null,
                  onPressed: () => setState(() => _endsAt = null),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.primary,
              value: _verified,
              onChanged: (value) => setState(() => _verified = value ?? false),
              title: const Text('Documentos verificados'),
              subtitle: Text(
                'Cartão de Cidadão, atividade nas Finanças e seguro, vistos '
                'na assinatura do contrato.',
                style: secondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _notesController,
            label: 'Notas do contrato',
            hintText: 'Só tu vês isto',
            maxLines: 3,
            textInputAction: TextInputAction.newline,
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(error,
                style: textTheme.bodySmall?.copyWith(color: AppStatusColor.cancelled.foreground)),
          ],
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final String value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary)),
            ),
            Text(value,
                style: textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textPrimary)),
            const SizedBox(width: AppSpacing.xxs),
            const Icon(Icons.edit_calendar_outlined,
                size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
