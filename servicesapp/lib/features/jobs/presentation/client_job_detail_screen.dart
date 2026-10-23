import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/phone_utils.dart';
import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../application/job_providers.dart';
import '../data/job_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../worker/application/worker_providers.dart';
import '../../../core/widgets/address_map_link.dart';
import '../../../core/widgets/app_whatsapp_button.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/photo_viewer_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/bottom_actions_bar.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../../core/widgets/status_timeline.dart';
import '../../../core/widgets/user_avatar_with_name.dart';
import '../../../core/widgets/service_icon.dart';
import '../application/job_labels.dart';
import '../application/job_timeline.dart';
import '../../../core/widgets/app_bar_title.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/submit_rating_sheet.dart';
import '../../client/application/client_create_job_wizard_provider.dart';
import '../../client/application/job_request_form.dart';
import '../../client/presentation/repeat_hire_launcher.dart';
import '../../client/presentation/widgets/direct_request_waiting_banner.dart';
import '../../client/presentation/widgets/no_proposals_help_card.dart';
import '../application/no_proposals_labels.dart';
import '../../client/presentation/widgets/repeat_hire_card.dart';
import '../application/direct_request_labels.dart';
import '../data/direct_request_models.dart';
import 'client_scheduled_job_detail_screen.dart';
import '../../../core/widgets/app_toast.dart';

class ClientJobDetailScreen extends ConsumerStatefulWidget {
  const ClientJobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<ClientJobDetailScreen> createState() =>
      _ClientJobDetailScreenState();
}

class _ClientJobDetailScreenState
    extends ConsumerState<ClientJobDetailScreen> {
  bool _saving = false;
  bool _confirming = false;
  bool _showCompletedFeedback = false;
  String? _selectedProblemId;

  /// Lista fixa só do lado do Flutter — sem coluna nova em `job_reports`
  /// (que só tem id/job_id/reporter_id/description/created_at). Ao
  /// selecionar, pré-preenche o texto livre existente; não muda o schema.
  static const _commonProblems = [
    (id: 'no_show', label: 'Não apareceu', prefill: 'O jardineiro responsável não apareceu. '),
    (id: 'late', label: 'Atraso', prefill: 'O jardineiro responsável chegou com atraso. '),
    (id: 'incomplete', label: 'Incompleto', prefill: 'O trabalho ficou incompleto. '),
  ];

  Future<void> _cancelJob() async {
    final job = ref.read(jobByIdProvider(widget.jobId)).value;
    if (job == null) return;

    // Open jobs have no confirmed worker — simple confirmation, no reason picker
    if (job.status == JobStatus.open) {
      final confirmed = await AppConfirmDialog.show(
        context,
        icon: Icons.event_busy_outlined,
        title: 'Cancelar pedido?',
        message: 'O pedido deixa de aparecer aos jardineiros. Não dá para '
            'desfazer.',
        confirmLabel: 'Cancelar pedido',
        destructive: true,
      );
      if (confirmed != true || !mounted) return;
      setState(() => _saving = true);
      final toast = AppToast.of(context);
      final router = GoRouter.of(context);
      var navigatedAway = false;
      try {
        await ref.read(jobRepositoryProvider).cancelJob(
              jobId: widget.jobId,
              reason: 'no_longer_needed',
              reasonDetail: null,
            );
        navigatedAway = true;
        router.go('/client/jobs');
        toast.show('Pedido cancelado.');
        ref.invalidate(clientJobsProvider);
        ref.invalidate(pendingProposalsForJobProvider(widget.jobId));
        ref.invalidate(jobByIdProvider(widget.jobId));
      } catch (e) {
        toast.error(friendlyError(e));
      } finally {
        if (!navigatedAway && mounted) setState(() => _saving = false);
      }
      return;
    }
  }

  /// "Publicar de novo": abre o wizard de criar pedido já preenchido com
  /// este pedido, no primeiro passo que precise de alguma coisa (data que
  /// já passou, por exemplo) ou logo na revisão.
  void _republish(JobRequest job, List<ServiceType> serviceTypes) {
    final draft = republishWizardState(
      job,
      now: DateTime.now(),
      // Catálogo ainda por carregar: assume que o serviço continua a existir.
      serviceStillOffered: serviceTypes.isEmpty ||
          serviceTypes.any((s) => s.id == job.serviceTypeId),
    );
    ref.read(clientCreateJobWizardProvider.notifier).startFrom(draft);
    context.push(wizardFirstIncompleteRoute(draft));
  }

  /// "Mostrar já a todos" (pedido direto, 0057). Sem passo otimista: em
  /// sucesso recarrega o pedido e a faixa muda; em erro devolve a mensagem
  /// para ficar dentro da faixa.
  Future<String?> _releaseDirectRequest() async {
    try {
      await ref
          .read(jobRepositoryProvider)
          .releaseDirectJobRequest(widget.jobId);
    } catch (e) {
      return friendlyError(e);
    }
    if (!mounted) return null;
    AppToast.of(context)
        .show('O pedido já está visível para todos os jardineiros.');
    ref.invalidate(jobByIdProvider(widget.jobId));
    ref.invalidate(clientJobsProvider);
    return null;
  }

  /// "Mostrar a jardineiros mais longe" (0062). Sem navegação: aviso e
  /// depois recarrega o pedido; em erro a mensagem fica no cartão.
  Future<String?> _widenSearch() async {
    final int extraKm;
    try {
      extraKm = await ref.read(jobRepositoryProvider).widenJobSearch(widget.jobId);
    } catch (e) {
      return friendlyError(e);
    }
    if (!mounted) return null;
    AppToast.of(context).show(widenedSearchToast(extraKm));
    ref.invalidate(jobByIdProvider(widget.jobId));
    ref.invalidate(clientJobsProvider);
    return null;
  }

  /// Cartão "Ainda sem propostas" (RC5): depois do aviso das 24h.
  Widget? _noProposalsCard(JobRequest job) {
    final texts = noProposalsHelpTexts(job);
    if (texts == null) return null;
    return NoProposalsHelpCard(
      data: NoProposalsHelpCardViewData(
        titleLabel: texts.title,
        descriptionLabel: texts.description,
        dateActionLabel: noProposalsDateActionLabel,
        descriptionActionLabel: noProposalsDescriptionActionLabel,
        widenActionLabel: texts.widenActionLabel,
      ),
      onEditRequest: _saving
          ? null
          : () => context.push('/client/job/${widget.jobId}/edit'),
      onWiden: _widenSearch,
    );
  }

  /// Faixa do pedido direto no pedido aberto: à espera do jardineiro
  /// escolhido, já aberto a todos porque ele recusou ou o prazo passou, ou
  /// parado à espera do cliente (interruptor desligado, 0059).
  Widget? _directBanner(JobRequest job) {
    final workerId = job.directWorkerId;
    if (job.status != JobStatus.open || workerId == null) return null;
    if (directBannerTexts(job, workerName: '') == null) return null;

    final infoAsync = ref.watch(workerBasicInfoProvider(workerId));
    if (infoAsync.isLoading && !infoAsync.hasValue) {
      return const DirectRequestWaitingBannerSkeleton();
    }
    final info = infoAsync.asData?.value ?? const <String, String>{};
    final name = info['full_name'] ?? '';
    final texts = directBannerTexts(job, workerName: name)!;
    final display = switch (texts.kind) {
      DirectBannerKind.waiting => DirectRequestWaitingDisplay.waiting,
      DirectBannerKind.onHold => DirectRequestWaitingDisplay.onHold,
      DirectBannerKind.released => DirectRequestWaitingDisplay.released,
    };
    final onHold = display == DirectRequestWaitingDisplay.onHold;
    return DirectRequestWaitingBanner(
      data: DirectRequestWaitingBannerViewData(
        display: display,
        titleLabel: texts.title,
        descriptionLabel: texts.description,
        workerInitial: initialOf(name.isEmpty ? 'Jardineiro' : name),
        workerAvatarUrl: info['avatar_url'],
        releaseActionLabel: switch (display) {
          DirectRequestWaitingDisplay.waiting => 'Mostrar já a todos',
          DirectRequestWaitingDisplay.onHold => 'Mostrar a todos',
          DirectRequestWaitingDisplay.released => null,
        },
        cancelActionLabel: onHold ? 'Cancelar pedido' : null,
      ),
      onReleaseToAll: _releaseDirectRequest,
      onCancelRequest: onHold && !_saving ? _cancelJob : null,
    );
  }

  /// Cartão "Precisas outra vez?": só com 4 ou 5 estrelas ou sem avaliação.
  RepeatHireCardViewData? _repeatHireViewData(
    RepeatHireInfo? info,
    List<ServiceType> serviceTypes,
  ) {
    if (info == null || !showRepeatHire(info)) return null;
    final name = firstNameOr(info.workerName, 'o jardineiro');
    final service = serviceTypes
            .where((s) => s.id == info.serviceTypeId)
            .map((s) => s.name)
            .firstOrNull ??
        '';
    final date = info.jobDate == null
        ? ''
        : DateFormat('dd/MM/yyyy').format(info.jobDate!);
    return RepeatHireCardViewData(
      workerName: info.workerName,
      workerAvatarUrl: info.workerAvatarUrl,
      previousJobLabel:
          [service, date].where((p) => p.isNotEmpty).join(', '),
      descriptionLabel: info.canRequest
          ? 'Pede de novo e o pedido vai primeiro para $name. Se não '
              'puder, fica visível para todos.'
          : 'Este jardineiro já não aceita pedidos. Podes criar um pedido '
              'novo para todos os jardineiros.',
    );
  }

  /// Devolve true só depois da RPC confirmar sucesso — a navegação/snackbar
  /// ficam em [_handleConfirmCompleted], que mostra o AppSuccessFeedback
  /// antes de sair do ecrã.
  Future<bool> _confirmJobCompletion() async {
    final confirmed = await AppConfirmDialog.show(
      context,
      icon: Icons.task_alt_rounded,
      title: 'Confirmar conclusão?',
      message: 'Confirmas que o trabalho ficou feito como combinado. '
          'Depois podes avaliar o jardineiro.',
      confirmLabel: 'Confirmar',
    );
    if (confirmed != true || !mounted) return false;

    setState(() => _confirming = true);
    final toast = AppToast.of(context);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .confirmJobCompletion(widget.jobId);
      return true;
    } catch (e) {
      toast.error(friendlyError(e));
      return false;
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  /// Depois de confirmar fica no próprio pedido (agora `completed`) e abre
  /// logo a avaliação: era o passo seguinte natural e, ao sair para a
  /// lista, ficava esquecido.
  Future<void> _handleConfirmCompleted() async {
    final success = await _confirmJobCompletion();
    if (!mounted || !success) return;

    setState(() => _showCompletedFeedback = true);
    final toast = AppToast.of(context);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    await Future<void>.delayed(
      disableAnimations ? Duration.zero : const Duration(milliseconds: 900),
    );
    if (!mounted) return;

    setState(() => _showCompletedFeedback = false);
    toast.show('Trabalho confirmado! Obrigado.');
    // Sem navegação: o ecrã fica e passa a mostrar o ramo `completed`.
    ref.invalidate(clientJobsProvider);
    ref.invalidate(jobByIdProvider(widget.jobId));
    ref.invalidate(myRatingForJobProvider(widget.jobId));
    await _showClientRatingSheet();
  }

  /// Fotos de antes e de depois e o tempo registado pelo jardineiro
  /// (migrations 0046 e 0052). Pedidos antigos só têm
  /// `completionPhotoPath`.
  Widget _workRecord(JobRequest job, ThemeData theme) {
    final repo = ref.read(jobRepositoryProvider);
    final after = job.afterPhotoPaths.isNotEmpty
        ? job.afterPhotoPaths
        : [?job.completionPhotoPath];
    final worked = job.workedDuration;

    Widget photoRow(String label, List<String> paths) {
      final urls = paths.map(repo.jobPhotoPublicUrl).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var i = 0; i < urls.length; i++)
                Semantics(
                  button: true,
                  label: '$label, foto ${i + 1}',
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          PhotoViewerScreen(photoUrls: urls, initialIndex: i),
                    )),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      child: Image.network(
                        urls[i],
                        width: AppSpacing.xl * 3,
                        height: AppSpacing.xl * 3,
                        fit: BoxFit.cover,
                        cacheWidth: 400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    return AppStaggeredEntrance(
      index: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (worked != null) ...[
            Text(
              'Tempo registado: ${durationLabel(worked)}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (job.beforePhotoPaths.isNotEmpty) ...[
            photoRow('Antes', job.beforePhotoPaths),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (after.isNotEmpty) photoRow('Depois', after),
        ],
      ),
    );
  }

  Future<void> _reportProblem({String prefillText = ''}) async {
    final formKey = GlobalKey<FormState>();
    final descController = TextEditingController(text: prefillText)
      ..selection = TextSelection.collapsed(offset: prefillText.length);
    final toast = AppToast.of(context);

    bool submitting = false;
    String? errorText;
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Reportar problema',
                      style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Descreve o que aconteceu. O teu relato fica registado para referência futura.',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: descController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Descrição do problema',
                      alignLabelWithHint: true,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 10) {
                        return 'Descreve o problema (mínimo 10 caracteres).';
                      }
                      return null;
                    },
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      errorText!,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: AppStatusColor.cancelled.foreground),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheetState(() {
                              submitting = true;
                              errorText = null;
                            });
                            try {
                              await ref
                                  .read(proposalRepositoryProvider)
                                  .reportJobProblem(
                                    jobId: widget.jobId,
                                    description: descController.text.trim(),
                                  );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              // Dentro da sheet: um SnackBar ficava
                              // escondido por trás dela.
                              if (!ctx.mounted) return;
                              setSheetState(() {
                                submitting = false;
                                errorText = friendlyError(e);
                              });
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Enviar relato'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    descController.dispose();
    if (submitted != true || !mounted) return;

    toast.show('Relato enviado. A nossa equipa vai analisar.');

    if (!mounted) return;
    final confirmAnyway = await AppConfirmDialog.show(
      context,
      icon: Icons.task_alt_rounded,
      title: 'Confirmar conclusão?',
      message: 'Queres confirmar a conclusão do trabalho mesmo assim?',
      confirmLabel: 'Sim, confirmar',
      cancelLabel: 'Ainda não',
    );
    if (confirmAnyway == true && mounted) {
      await _handleConfirmCompleted();
    }
  }

  Widget _workerContactCardSkeleton() {
    return AppSkeletonShimmer(
      child: Container(
        height: 112,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
    );
  }

  Widget _workerContactCard(
    JobRequest job,
    AsyncValue<Map<String, String>> workerInfoAsync,
    ThemeData theme,
  ) {
    return workerInfoAsync.when(
      loading: _workerContactCardSkeleton,
      error: (e, _) =>
          const Text('Não foi possível carregar o contacto.'),
      data: (info) {
        if (info.isEmpty) {
          return _workerContactCardSkeleton();
        }
        final name = info['full_name'] ?? '';
        final phone = info['phone'] ?? '';
        final avatarUrl = info['avatar_url'];
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UserAvatarWithName(
                name: name,
                avatarUrl: avatarUrl,
                fallbackLabel: 'Jardineiro',
              ),
              if (job.confirmedDate != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(children: [
                  const Icon(Icons.event_available_outlined,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      _formatConfirmedSchedule(job),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: AppSpacing.sm),
              AppWhatsAppButton(
                onPressed: phone.isEmpty
                    ? null
                    : () => openWhatsAppOrWarn(context, phone),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(jobByIdProvider(widget.jobId)).when(
      loading: () => const Scaffold(
        body: AppScreenLoadingSkeleton(),
      ),
      error: (e, _) => _JobDetailMessage(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(jobByIdProvider(widget.jobId)),
      ),
      data: (job) {
        if (job == null) {
          return const _JobDetailMessage(message: 'Pedido não encontrado.');
        }

        // `confirmed` tem ecrã próprio (doc.txt, "7b. Detalhe do pedido
        // agendado/confirmado") — delega sem mudar de rota, antes de watchar
        // providers que só interessam aos outros ramos.
        if (job.status == JobStatus.confirmed) {
          return ClientScheduledJobDetailScreen(jobId: widget.jobId);
        }

        final theme = Theme.of(context);

        // Watch all providers unconditionally inside data branch
        final acceptedProposalAsync =
            ref.watch(acceptedProposalForJobProvider(widget.jobId));
        final photosAsync = ref.watch(jobPhotosProvider(widget.jobId));

        final workerId = acceptedProposalAsync.asData?.value?.workerId ?? '';
        final workerInfoAsync = ref.watch(workerBasicInfoProvider(workerId));

        final ratingAsync = ref.watch(myRatingForJobProvider(job.id));

        // Mesma instância usada no badge do AppBar e na legenda de apoio do
        // timeline — garante a "regra definitiva de mesma cor para badge +
        // timeline do mesmo estado".
        final statusPresentation = job.status.presentation(
          proposalCount: job.proposalCount,
        );
        // Margem direita consistente (AppSpacing.md) nos dois ramos —
        // serve também de espaçamento para o ícone de fechar, no ramo
        // `open`.
        final statusBadge =
            AppBarStatusBadge.fromPresentation(presentation: statusPresentation);

        final photosWidget = photosAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (urls) {
            if (urls.isEmpty) return const SizedBox.shrink();
            return AppStaggeredEntrance(
              index: 4,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fotos',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: urls.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: AppSpacing.xs),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => PhotoViewerScreen(
                              photoUrls: urls,
                              initialIndex: i,
                            ),
                          )),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.input),
                            child: Image.network(
                              urls[i],
                              width: 72,
                              height: 72,
                              // Miniatura: descodifica perto do tamanho mostrado
                              // em vez dos 800 px da foto original.
                              cacheWidth: 300,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );

        final serviceTypesForDetail =
            ref.watch(serviceTypesProvider).asData?.value ?? const [];
        final serviceTypeName = serviceTypesForDetail
                .where((s) => s.id == job.serviceTypeId)
                .map((s) => s.name)
                .firstOrNull ??
            '—';

        // "Publicado→Propostas→Escolher→Confirmado" só faz sentido enquanto
        // o pedido ainda não tem worker escolhido — para os restantes
        // estados usa-se buildJobTimeline (partilhado com o lado do worker).
        final timelineSteps = job.status == JobStatus.open
            ? _buildOpenStepperSteps(job)
            : buildJobTimeline(job);

        // Shared: banners + timeline + resumo + metadata + descrição + fotos
        final detailChildren = <Widget>[
          if (job.reopenedFrom != null)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Este pedido foi criado automaticamente após o cancelamento de um pedido anterior.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.primaryPressed),
                    ),
                  ),
                ],
              ),
            ),
          AppStaggeredEntrance(
            index: 0,
            child: StatusTimelineCard(
              steps: timelineSteps,
              supportingLabel:
                  job.status == JobStatus.open ? openJobExpiryNotice(job) : null,
              supportingLabelColor: statusPresentation.color.foreground,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: 1,
            child: _ServiceSummaryRow(
              icon: serviceTypeIconFor(
                  serviceTypesForDetail, job.serviceTypeId),
              serviceLabel: serviceTypeName,
              metadataLabel: job.addressText.isNotEmpty
                  ? job.addressText
                  : 'Localização não especificada',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: 2,
            child: _JobMetadataCard(
              dateRowLabel: job.dateMode == DateMode.availability
                  ? 'Disponibilidade'
                  : 'Data preferida',
              preferredDateLabel: _preferredDateLabel(job),
              urgencyLabel: job.urgency == Urgency.urgent ? 'Urgente' : 'Normal',
              sizeLabel: job.sizeEstimate?.label,
            ),
          ),
          if (job.locationLat != 0 || job.locationLng != 0) ...[
            const SizedBox(height: AppSpacing.sm),
            AddressMapLink(
              address: job.addressText,
              lat: job.locationLat,
              lng: job.locationLng,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Descrição',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  job.description,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          photosWidget,
        ];

        // ── Open status: single scroll + "Ver propostas" no fundo ────────────────

        if (job.status == JobStatus.open) {
          final directBanner = _noProposalsCard(job) ?? _directBanner(job);
          if (directBanner != null) {
            detailChildren.insertAll(0, [
              directBanner,
              const SizedBox(height: AppSpacing.md),
            ]);
          }
          final proposalsButtonLabel = job.proposalCount > 0
              ? 'Ver propostas (${job.proposalCount})'
              : 'Ver propostas';

          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: AppColors.surface,
              surfaceTintColor: AppColors.surface,
              elevation: 0,
              leading: const AppBackButton(),
              title: AppBarTitle(
                title: serviceTypeName,
                subtitle: jobDistinguisherLabel(job),
              ),
              actions: [
                statusBadge,
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  tooltip: 'Cancelar pedido',
                  onPressed: _saving ? null : _cancelJob,
                ),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: detailChildren,
                      ),
                    ),
                  ),
                  BottomActionsBar(children: [
                    PrimaryActionButton(
                      label: proposalsButtonLabel,
                      onPressed: () =>
                          context.push('/client/job/${widget.jobId}/proposals'),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => context
                                .push('/client/job/${widget.jobId}/edit'),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar pedido'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          );
        }

        // ── Awaiting confirmation: worker marked done, client confirms or reports ──

        Widget? bottomBar;

        if (job.status == JobStatus.awaitingConfirmation) {
          final selectedProblem = _commonProblems
              .where((p) => p.id == _selectedProblemId)
              .firstOrNull;

          detailChildren.add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _workerContactCard(job, workerInfoAsync, theme),
                const SizedBox(height: AppSpacing.md),
                if (job.workedDuration != null ||
                    job.beforePhotoPaths.isNotEmpty ||
                    job.afterPhotoPaths.isNotEmpty ||
                    job.completionPhotoPath != null) ...[
                  _workRecord(job, theme),
                  const SizedBox(height: AppSpacing.md),
                ],
                AppStaggeredEntrance(
                  index: 5,
                  child: Text(
                    'Como correu o trabalho?',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Confirma a conclusão ou reporta um problema. Sem resposta, '
                  'fica confirmado automaticamente 48 horas depois de o '
                  'jardineiro o dar por concluído. Depois de confirmares, '
                  'podes avaliar o jardineiro.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Problemas comuns',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final problem in _commonProblems)
                      AppFilterChip(
                        label: problem.label,
                        selected: _selectedProblemId == problem.id,
                        onPressed: () {
                          setState(() {
                            _selectedProblemId =
                                _selectedProblemId == problem.id
                                    ? null
                                    : problem.id;
                          });
                        },
                      ),
                  ],
                ),
              ],
            ),
          );

          bottomBar = BottomActionsBar(children: [
            PrimaryActionButton(
              label: 'Trabalho concluído',
              isLoading: _confirming,
              onPressed: _confirming ? null : _handleConfirmCompleted,
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _confirming
                    ? null
                    : () => _reportProblem(
                          prefillText: selectedProblem?.prefill ?? '',
                        ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppStatusColor.cancelled.foreground,
                  side: BorderSide(color: AppStatusColor.cancelled.foreground),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                ),
                icon: const Icon(Icons.error_outline_rounded),
                label: const Text('Reportar problema'),
              ),
            ),
          ]);
        }

        if (canRepublishJob(job)) {
          bottomBar = BottomActionsBar(children: [
            PrimaryActionButton(
              label: 'Publicar de novo',
              onPressed: () => _republish(job, serviceTypesForDetail),
            ),
          ]);
        }

        if (job.status == JobStatus.completed) {
          detailChildren.add(_workerContactCard(job, workerInfoAsync, theme));
          detailChildren.add(const SizedBox(height: AppSpacing.md));
          detailChildren.add(_buildClientRatingSection(theme, ratingAsync));

          // "Precisas outra vez?" (pedido direto, 0057). O botão fica na
          // barra do fundo; sem barra quando o cartão não aparece ou falha.
          final repeatAsync = ref.watch(repeatHireForJobProvider(job.id));
          final repeatData = repeatAsync.whenData(
            (info) => _repeatHireViewData(info, serviceTypesForDetail),
          );
          detailChildren.add(const SizedBox(height: AppSpacing.md));
          detailChildren.add(RepeatHireCard(
            dataAsync: repeatData,
            entranceIndex: 6,
            onRetry: () => ref.invalidate(repeatHireForJobProvider(job.id)),
          ));

          final repeatInfo = repeatAsync.asData?.value;
          if (repeatAsync.isLoading && !repeatAsync.hasValue) {
            bottomBar = const BottomActionsBar(children: [
              PrimaryActionButton(label: 'Pedir de novo', onPressed: null),
            ]);
          } else if (repeatInfo != null && repeatData.asData?.value != null) {
            final name = firstNameOr(repeatInfo.workerName, '');
            bottomBar = BottomActionsBar(children: [
              repeatInfo.canRequest
                  ? PrimaryActionButton(
                      label: name.isEmpty
                          ? 'Pedir de novo'
                          : 'Pedir de novo a $name',
                      onPressed: () => startRepeatHire(
                        context,
                        ref,
                        sourceJob: job,
                        workerName: repeatInfo.workerName,
                        workerAvatarUrl: repeatInfo.workerAvatarUrl,
                      ),
                    )
                  : PrimaryActionButton(
                      label: 'Criar novo pedido',
                      onPressed: () => _republish(job, serviceTypesForDetail),
                    ),
            ]);
          }

          // Entrada única para avaliar: o cartão "Avaliar agora" acima
          // (`submit_client_rating`, cobre o jardineiro e os ajudantes) e
          // que passa a "Trabalho avaliado" depois. O antigo botão
          // "Avaliar profissional" chamava `submit_principal_rating`, que
          // recusa sempre o cliente, e foi removido.
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: AppColors.background,
            elevation: 0,
            leading: const AppBackButton(),
            title: AppBarTitle(
              title: serviceTypeName,
              subtitle: jobDistinguisherLabel(job),
            ),
            actions: [statusBadge],
          ),
          body: Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: detailChildren,
                        ),
                      ),
                    ),
                    ?bottomBar,
                  ],
                ),
              ),
              Positioned.fill(
                child: AppSuccessFeedback(
                  visible: _showCompletedFeedback,
                  message: 'Trabalho confirmado',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClientRatingSection(
      ThemeData theme, AsyncValue<Rating?> ratingAsync) {
    return ratingAsync.when(
      loading: () => AppSkeletonShimmer(
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (existing) {
        if (existing != null) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.check_circle,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Text('Trabalho avaliado',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: AppColors.textPrimary)),
                ]),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < existing.stars
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 18,
                      color: AppColors.logoAccent,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Avaliar o trabalho',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: AppColors.textPrimary)),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Partilha a tua experiência com o jardineiro responsável e os ajudantes.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              FilledButton.tonal(
                onPressed: _showClientRatingSheet,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                ),
                child: const Text('Avaliar agora'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showClientRatingSheet() async {
    final submitted = await showSubmitRatingSheet(
      context: context,
      title: 'Avaliar o trabalho',
      subtitle:
          'A nota é partilhada com o jardineiro responsável e os ajudantes. O comentário aparece no perfil do jardineiro responsável.',
      successMessage:
          'Avaliação enviada! Cobre o jardineiro responsável e os ajudantes deste trabalho.',
      onSubmit: (stars, comment) async {
        await ref.read(ratingRepositoryProvider).submitClientRating(
              jobId: widget.jobId,
              stars: stars,
              comment: comment,
            );
      },
    );
    if (submitted != true || !mounted) return;
    ref.invalidate(myRatingForJobProvider(widget.jobId));
    // A nota decide se o cartão "Precisas outra vez?" aparece.
    ref.invalidate(repeatHireForJobProvider(widget.jobId));
    ref.invalidate(myPreviousWorkersProvider);
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

/// Data do pedido: a data fixa, o texto de disponibilidade ou "Flexível".
String _preferredDateLabel(JobRequest job) {
  if (job.dateMode == DateMode.availability) {
    final text = job.availabilityText?.trim() ?? '';
    return text.isEmpty ? 'A combinar' : text;
  }
  if (job.preferredDate == null) return 'Flexível';
  return DateFormat('dd/MM/yyyy').format(job.preferredDate!);
}

String _formatConfirmedSchedule(JobRequest job) {
  if (job.confirmedDate == null) return '';
  final date = DateFormat('dd/MM/yyyy').format(job.confirmedDate!);
  if (job.confirmedFlexible) return 'Agendado para: $date (horário flexível)';
  if (job.confirmedTime != null) {
    return 'Agendado para: $date às ${job.confirmedTime}';
  }
  return 'Agendado para: $date';
}

// ── Ecrã 5 — timeline de 4 estágios (só JobStatus.open) ───────────────────

/// "Publicado → Propostas → Escolher → Confirmado".
///
/// Propostas/Escolher são dois estágios visuais sobre o mesmo
/// `JobStatus.open` — distinguidos só por `job.proposalCount`, sem estado
/// novo no backend. "Confirmado" está sempre `future` aqui porque, por
/// definição, um job com este stepper ainda não tem proposta aceite.
List<StatusTimelineStepData> _buildOpenStepperSteps(JobRequest job) {
  final hasProposals = job.proposalCount > 0;
  return [
    StatusTimelineStepData(
      label: 'Publicado',
      statusColor: AppStatusColor.success,
      state: StatusTimelineStepState.completed,
      subtitle: DateFormat('dd/MM/yyyy').format(job.createdAt),
    ),
    StatusTimelineStepData(
      label: 'Propostas',
      statusColor: AppStatusColor.waiting,
      state: hasProposals
          ? StatusTimelineStepState.completed
          : StatusTimelineStepState.current,
      subtitle: hasProposals
          ? '${job.proposalCount} ${job.proposalCount == 1 ? 'proposta' : 'propostas'}'
          : null,
    ),
    StatusTimelineStepData(
      label: 'Escolher',
      statusColor: AppStatusColor.waiting,
      state: hasProposals
          ? StatusTimelineStepState.current
          : StatusTimelineStepState.future,
    ),
    const StatusTimelineStepData(
      label: 'Confirmado',
      statusColor: AppStatusColor.neutral,
      state: StatusTimelineStepState.future,
    ),
  ];
}

/// Ecrã de erro/pedido inexistente com saída (voltar ou ir para o início)
/// e, quando faz sentido, "Tentar novamente".
class _JobDetailMessage extends StatelessWidget {
  const _JobDetailMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: const AppBackButton(),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AppStaggeredEntrance(
              index: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceSummaryRow extends StatelessWidget {
  const _ServiceSummaryRow({
    required this.icon,
    required this.serviceLabel,
    required this.metadataLabel,
  });

  final IconData icon;
  final String serviceLabel;
  final String metadataLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                serviceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                metadataLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _JobMetadataCard extends StatelessWidget {
  const _JobMetadataCard({
    required this.dateRowLabel,
    required this.preferredDateLabel,
    required this.urgencyLabel,
    this.sizeLabel,
  });

  final String dateRowLabel;
  final String preferredDateLabel;
  final String urgencyLabel;
  final String? sizeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _MetadataRow(
            label: dateRowLabel,
            value: preferredDateLabel,
            valueMaxLines: 3,
          ),
          const SizedBox(height: AppSpacing.sm),
          _MetadataRow(label: 'Urgência', value: urgencyLabel),
          if (sizeLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _MetadataRow(label: 'Dimensão', value: sizeLabel!),
          ],
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.label,
    required this.value,
    this.valueMaxLines = 1,
  });

  final String label;
  final String value;
  final int valueMaxLines;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // Flexible + ellipsis de propósito — o valor deixou de ser sempre
        // curto ("Pequeno"/"Médio"/"Grande") desde que os labels de
        // dimensão passaram a incluir a faixa de m² ("Médio (100-300m²)"),
        // e um `Text` solto sem constraint nenhuma dava overflow.
        Flexible(
          child: Text(
            value,
            maxLines: valueMaxLines,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

