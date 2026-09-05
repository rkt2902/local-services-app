import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../worker/application/worker_providers.dart';
import '../application/help_request_providers.dart';

/// Dados já resolvidos para preencher o formulário — montados a partir de
/// [helpRequestSummaryByIdProvider] + [serviceTypesProvider].
class _ApplyViewData {
  const _ApplyViewData({
    required this.helpRequestId,
    required this.title,
    required this.responsibleName,
    required this.paymentPerHelperLabel,
    required this.scheduleLabel,
    required this.equipmentRequired,
  });

  final String helpRequestId;
  final String title;
  final String responsibleName;
  final String paymentPerHelperLabel;
  final String scheduleLabel;
  final bool equipmentRequired;
}

/// Ecrã "Candidatar-me para ajudar" (rota `/worker/help-requests/:id/apply`).
///
/// Substitui a submissão inline que existia no botão "Candidatar-me" da tab
/// "Descobrir" (`worker_help_requests_screen.dart`). Mostra o pagamento e o
/// horário reais (migration 0034), exige confirmação explícita de
/// disponibilidade e permite uma mensagem opcional ao responsável.
class ApplyAsHelperScreen extends ConsumerStatefulWidget {
  const ApplyAsHelperScreen({super.key, required this.helpRequestId});

  final String helpRequestId;

  @override
  ConsumerState<ApplyAsHelperScreen> createState() =>
      _ApplyAsHelperScreenState();
}

class _ApplyAsHelperScreenState extends ConsumerState<ApplyAsHelperScreen> {
  final TextEditingController _messageController = TextEditingController();

  bool _availabilityConfirmed = false;
  bool _submitting = false;
  bool _showSuccessFeedback = false;
  Timer? _successTimer;

  /// Snapshot da última leitura válida — evita que o ecrã "desapareça" depois
  /// de submeter com sucesso, já que o submit invalida
  /// `helpRequestSummariesInRadiusProvider` (o pedido deixa de constar da
  /// lista, por já existir uma candidatura do próprio worker).
  _ApplyViewData? _snapshot;

  @override
  void dispose() {
    _messageController.dispose();
    _successTimer?.cancel();
    super.dispose();
  }

  static String _scheduleLabel(DateTime? date, String? time) {
    if (date == null) return 'Horário a combinar com o responsável';
    final dateStr = DateFormat('dd/MM/yyyy').format(date);
    if (time == null || time.isEmpty) return dateStr;
    final timeStr = time.length >= 5 ? time.substring(0, 5) : time;
    return '$dateStr às $timeStr';
  }

  _ApplyViewData? _resolveViewData() {
    final summary =
        ref.watch(helpRequestSummaryByIdProvider(widget.helpRequestId));
    if (summary == null) return null;
    final serviceTypes = ref.watch(serviceTypesProvider).asData?.value;
    if (serviceTypes == null) return null;
    final serviceTypeName = serviceTypes
            .where((t) => t.id == summary.serviceTypeId)
            .firstOrNull
            ?.name ??
        '—';

    return _ApplyViewData(
      helpRequestId: summary.id,
      title: serviceTypeName,
      responsibleName: summary.principalName,
      paymentPerHelperLabel: summary.paymentPerHelper > 0
          ? '€${summary.paymentPerHelper.toStringAsFixed(2)}/hora'
          : 'A combinar',
      scheduleLabel: _scheduleLabel(summary.confirmedDate, summary.confirmedTime),
      equipmentRequired: summary.equipmentRequired,
    );
  }

  Future<void> _submit() async {
    final data = _snapshot;
    if (data == null || !_availabilityConfirmed || _submitting) return;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(helpRequestRepositoryProvider).applyToHelpRequest(
            helpRequestId: data.helpRequestId,
            // Mantido igual ao comportamento atual: o worker não escolhe —
            // copia sempre a exigência do pedido. Ver nota no relatório.
            broughtEquipment: data.equipmentRequired,
            message: _messageController.text.trim().isEmpty
                ? null
                : _messageController.text.trim(),
          );
      if (!mounted) return;
      ref.invalidate(helpRequestSummariesInRadiusProvider);

      final disableAnimations =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      setState(() {
        _submitting = false;
        _showSuccessFeedback = true;
      });

      _successTimer?.cancel();
      _successTimer = Timer(
        disableAnimations
            ? const Duration(milliseconds: 300)
            : const Duration(milliseconds: 1100),
        () {
          if (!mounted) return;
          context.pop(true);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(SnackBar(
        content: Text(friendlyError(e)),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveViewData();
    if (resolved != null) _snapshot = resolved;
    final data = _snapshot;

    final radiusAsync = ref.watch(helpRequestSummariesInRadiusProvider);
    final hasError = data == null && radiusAsync.hasError;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: data == null
            ? (hasError ? _buildError() : const _ApplyLoading())
            : _buildForm(context, data),
      ),
    );
  }

  Widget _buildError() {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Não foi possível carregar este pedido de ajuda.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(helpRequestSummariesInRadiusProvider),
                    child: Text(
                      'Tentar novamente',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context, _ApplyViewData data) {
    final textTheme = Theme.of(context).textTheme;

    return Stack(
      children: [
        Column(
          children: [
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Candidatar-me',
                    style: textTheme.titleLarge
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStaggeredEntrance(
                      index: 0,
                      child: _JobSummaryCard(data: data),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 1,
                      child: _PaymentCard(data: data),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Confirmar disponibilidade',
                            style: textTheme.titleMedium
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _AvailabilityCard(
                            label: data.scheduleLabel,
                            selected: _availabilityConfirmed,
                            onTap: () => setState(
                              () => _availabilityConfirmed =
                                  !_availabilityConfirmed,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 3,
                      child: AppTextField(
                        controller: _messageController,
                        label: 'Mensagem ao responsável (opcional)',
                        hintText:
                            'Escreve uma mensagem curta para o responsável',
                        minLines: 3,
                        maxLines: 4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 4,
                      child: _InfoBox(),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: PrimaryActionButton(
                label: 'Enviar candidatura',
                isLoading: _submitting,
                onPressed: _availabilityConfirmed && !_submitting
                    ? _submit
                    : null,
              ),
            ),
          ],
        ),
        Positioned.fill(
          child: AppSuccessFeedback(
            visible: _showSuccessFeedback,
            message: 'Candidatura enviada',
          ),
        ),
      ],
    );
  }
}

class _JobSummaryCard extends StatelessWidget {
  const _JobSummaryCard({required this.data});

  final _ApplyViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            alignment: Alignment.center,
            // MVP é mono-categoria (jardinagem) — mesmo ícone estático usado
            // em worker_available_jobs_screen.dart (serviceTypeIconOf).
            child: const Icon(Icons.yard_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: textTheme.titleMedium
                      ?.copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Responsável: ${data.responsibleName}',
                  style: textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.data});

  final _ApplyViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pagamento por ajudante',
                  style: textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  data.paymentPerHelperLabel,
                  style:
                      textTheme.displaySmall?.copyWith(color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Horário',
                  style: textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  data.scheduleLabel,
                  textAlign: TextAlign.end,
                  style: textTheme.titleMedium
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected ? AppColors.primaryContainer : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_available_outlined,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: textTheme.titleMedium
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              AppFadeThroughSwitcher(
                switchKey: selected,
                child: selected
                    ? const AppPulseScale(
                        child: Icon(Icons.check_circle_outline,
                            color: AppColors.primary),
                      )
                    : const Icon(Icons.circle_outlined,
                        color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppStatusColor.info.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppStatusColor.info.foreground),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Se for aceite, este trabalho entra em "Os meus trabalhos" como Ajudante.',
              style: textTheme.labelMedium
                  ?.copyWith(color: AppStatusColor.info.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplyLoading extends StatelessWidget {
  const _ApplyLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          AppSkeletonShimmer(
            child: Container(
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppSkeletonShimmer(
            child: Container(
              height: 82,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
