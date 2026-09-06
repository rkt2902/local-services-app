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
///
/// `paymentPerHelper` é o valor devolvido pela RPC (migration 0034) para o
/// cenário por omissão: taxa cheia se `equipmentRequired`, ou 70% da taxa
/// caso contrário (mesma fórmula usada em
/// `WorkerHelpRequestsLobbyScreen._suggestedRate`). Quando o equipamento não
/// é obrigatório, o ecrã deixa o worker escolher se ainda assim leva o seu
/// — nesse caso o pagamento sobe para a taxa cheia, derivada aqui como
/// `paymentPerHelper / 0.7` (a RPC só devolve o valor já reduzido).
class _ApplyViewData {
  const _ApplyViewData({
    required this.helpRequestId,
    required this.title,
    required this.responsibleName,
    required this.paymentPerHelper,
    required this.scheduleLabel,
    required this.equipmentRequired,
  });

  final String helpRequestId;
  final String title;
  final String responsibleName;
  final double paymentPerHelper;
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

  /// Se o worker vai levar equipamento próprio. Quando o pedido exige
  /// equipamento (`equipmentRequired == true`) isto é obrigatório e fica
  /// bloqueado a `true` — não há escolha real, só confirmação. Quando não é
  /// exigido, é uma escolha genuína do worker que muda o pagamento (ver
  /// `_displayedRate`).
  bool _bringOwnEquipment = false;

  /// Snapshot da última leitura válida — evita que o ecrã "desapareça" depois
  /// de submeter com sucesso, já que o submit invalida
  /// `helpRequestSummariesInRadiusProvider` (o pedido deixa de constar da
  /// lista, por já existir uma candidatura do próprio worker).
  _ApplyViewData? _snapshot;

  /// `true` só na primeira vez que os dados de [helpRequestId] resolvem —
  /// usado para inicializar `_bringOwnEquipment` sem sobrepor uma escolha
  /// já feita pelo worker em builds seguintes.
  String? _initializedHelpRequestId;

  /// Taxa efetivamente paga: cheia se o equipamento é obrigatório, ou se o
  /// worker escolheu trazer o seu por iniciativa própria; 70% caso
  /// contrário. A RPC só devolve o valor já reduzido (`paymentPerHelper`)
  /// para o cenário por omissão — a taxa cheia deriva-se dividindo por 0.7,
  /// evitando expor `hourly_rate` bruto numa RPC pensada para descoberta.
  double _displayedRate(_ApplyViewData data) {
    if (data.equipmentRequired) return data.paymentPerHelper;
    if (data.paymentPerHelper <= 0) return 0;
    final fullRate = data.paymentPerHelper / 0.7;
    return _bringOwnEquipment ? fullRate : data.paymentPerHelper;
  }

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
      paymentPerHelper: summary.paymentPerHelper,
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
            // Obrigatório → sempre true (bloqueado na UI). Opcional → o que
            // o worker escolheu no _EquipmentCard.
            broughtEquipment:
                data.equipmentRequired ? true : _bringOwnEquipment,
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

    if (data != null && _initializedHelpRequestId != data.helpRequestId) {
      _initializedHelpRequestId = data.helpRequestId;
      _bringOwnEquipment = data.equipmentRequired;
    }

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
                      child: _PaymentCard(
                        paymentLabel: _displayedRate(data) > 0
                            ? '€${_displayedRate(data).toStringAsFixed(2)}/hora'
                            : 'A combinar',
                        scheduleLabel: data.scheduleLabel,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Equipamento',
                            style: textTheme.titleMedium
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _EquipmentCard(
                            required: data.equipmentRequired,
                            bringOwnEquipment: _bringOwnEquipment,
                            fullRateLabel: data.paymentPerHelper > 0
                                ? '€${(data.paymentPerHelper / 0.7).toStringAsFixed(2)}/hora'
                                : null,
                            reducedRateLabel: data.paymentPerHelper > 0
                                ? '€${data.paymentPerHelper.toStringAsFixed(2)}/hora'
                                : null,
                            onChanged: (value) =>
                                setState(() => _bringOwnEquipment = value),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 3,
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
                      index: 4,
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
                      index: 5,
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
  const _PaymentCard({
    required this.paymentLabel,
    required this.scheduleLabel,
  });

  /// Reativo à escolha de equipamento — ver `_displayedRate` no ecrã.
  final String paymentLabel;
  final String scheduleLabel;

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
                AppFadeThroughSwitcher(
                  switchKey: paymentLabel,
                  child: Text(
                    paymentLabel,
                    key: ValueKey(paymentLabel),
                    style: textTheme.displaySmall
                        ?.copyWith(color: AppColors.primary),
                  ),
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
                  scheduleLabel,
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

/// Mostra a exigência de equipamento do pedido e, quando não é obrigatório,
/// deixa o worker escolher se ainda assim leva o seu — essa escolha muda o
/// pagamento mostrado em [_PaymentCard] (ver `_displayedRate`).
class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({
    required this.required,
    required this.bringOwnEquipment,
    required this.onChanged,
    this.fullRateLabel,
    this.reducedRateLabel,
  });

  final bool required;
  final bool bringOwnEquipment;
  final ValueChanged<bool> onChanged;
  final String? fullRateLabel;
  final String? reducedRateLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (required) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppStatusColor.waiting.background,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.build, color: AppStatusColor.waiting.foreground),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Este trabalho requer equipamento próprio',
                    style: textTheme.titleSmall?.copyWith(
                      color: AppStatusColor.waiting.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Vais precisar de levar as tuas ferramentas para este trabalho.',
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppStatusColor.waiting.foreground),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final subtitle = fullRateLabel != null && reducedRateLabel != null
        ? 'Se levares, o pagamento sobe para $fullRateLabel (em vez de $reducedRateLabel).'
        : 'Levar equipamento próprio aumenta o pagamento por hora.';

    return Material(
      color: bringOwnEquipment ? AppColors.primaryContainer : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: () => onChanged(!bringOwnEquipment),
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(
              color:
                  bringOwnEquipment ? AppColors.primary : AppColors.divider,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.build_outlined,
                color: bringOwnEquipment
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vou levar o meu equipamento',
                      style: textTheme.titleMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppFadeThroughSwitcher(
                switchKey: bringOwnEquipment,
                child: bringOwnEquipment
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
