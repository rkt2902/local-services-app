import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/enums.dart';
import '../../../core/utils/error_utils.dart';
import '../application/job_providers.dart';
import '../data/job_model.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../worker/application/worker_providers.dart';
import '../../../core/widgets/address_map_link.dart';
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
import '../application/job_timeline.dart';
import '../../ratings/application/rating_providers.dart';
import '../../ratings/presentation/rating_sheet.dart';
import 'client_scheduled_job_detail_screen.dart';

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
    (id: 'no_show', label: 'Não apareceu', prefill: 'O prestador não apareceu — '),
    (id: 'late', label: 'Atraso', prefill: 'O prestador chegou com atraso — '),
    (id: 'incomplete', label: 'Incompleto', prefill: 'O trabalho ficou incompleto — '),
  ];

  Future<void> _cancelJob() async {
    final job = ref.read(jobByIdProvider(widget.jobId)).value;
    if (job == null) return;

    // Open jobs have no confirmed worker — simple confirmation, no reason picker
    if (job.status == JobStatus.open) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Cancelar pedido?'),
          content:
              const Text('Tens a certeza que queres cancelar este pedido?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Voltar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cancelar pedido'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _saving = true);
      final scaffold = ScaffoldMessenger.of(context);
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
        scaffold.showSnackBar(
            const SnackBar(content: Text('Pedido cancelado.')));
        ref.invalidate(clientJobsProvider);
        ref.invalidate(pendingProposalsForJobProvider(widget.jobId));
      } catch (e) {
        scaffold.showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      } finally {
        if (!navigatedAway && mounted) setState(() => _saving = false);
      }
      return;
    }
  }

  /// Devolve true só depois da RPC confirmar sucesso — a navegação/snackbar
  /// ficam em [_handleConfirmCompleted], que mostra o AppSuccessFeedback
  /// antes de sair do ecrã.
  Future<bool> _confirmJobCompletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Confirmar conclusão'),
        content: const Text(
            'Confirmas que o trabalho foi concluído conforme esperado?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    setState(() => _confirming = true);
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(proposalRepositoryProvider)
          .confirmJobCompletion(widget.jobId);
      ref.invalidate(clientJobsProvider);
      return true;
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(
            content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
      return false;
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  Future<void> _handleConfirmCompleted() async {
    final success = await _confirmJobCompletion();
    if (!mounted || !success) return;

    setState(() => _showCompletedFeedback = true);
    final scaffold = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    await Future<void>.delayed(
      disableAnimations ? Duration.zero : const Duration(milliseconds: 900),
    );
    if (!mounted) return;

    setState(() => _showCompletedFeedback = false);
    scaffold.showSnackBar(
      const SnackBar(content: Text('Trabalho confirmado! Obrigado.')),
    );
    router.go('/client/jobs');
  }

  Future<void> _reportProblem({String prefillText = ''}) async {
    final formKey = GlobalKey<FormState>();
    final descController = TextEditingController(text: prefillText)
      ..selection = TextSelection.collapsed(offset: prefillText.length);
    final scaffold = ScaffoldMessenger.of(context);

    bool submitting = false;
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
                  const SizedBox(height: 8),
                  Text(
                    'Descreve o que aconteceu. O teu relato fica registado para referência futura.',
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            setSheetState(() => submitting = true);
                            try {
                              await ref
                                  .read(proposalRepositoryProvider)
                                  .reportJobProblem(
                                    jobId: widget.jobId,
                                    description: descController.text.trim(),
                                  );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              setSheetState(() => submitting = false);
                              scaffold.showSnackBar(SnackBar(
                                  content: Text(friendlyError(e)),
                                  backgroundColor: Colors.red));
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

    scaffold.showSnackBar(
      const SnackBar(
          content: Text('Relato enviado. A nossa equipa vai analisar.')),
    );

    if (!mounted) return;
    final confirmAnyway = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Confirmar conclusão?'),
        content: const Text(
            'Queres confirmar a conclusão do trabalho mesmo assim?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Ainda não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Sim, confirmar'),
          ),
        ],
      ),
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
              UserAvatarWithName(name: name, avatarUrl: avatarUrl),
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
              FilledButton.icon(
                onPressed: phone.isEmpty
                    ? null
                    : () async {
                        final clean =
                            phone.replaceAll(RegExp(r'[\s\-]'), '');
                        final uri = Uri.parse('https://wa.me/$clean');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                style: FilledButton.styleFrom(
                  elevation: 0,
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                ),
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Contactar via WhatsApp'),
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
      error: (e, _) => Scaffold(
        body: SafeArea(child: Center(child: Text(friendlyError(e)))),
      ),
      data: (job) {
        if (job == null) {
          return const Scaffold(
            body: SafeArea(child: Center(child: Text('Pedido não encontrado.'))),
          );
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
        final statusBadge =
            AppStatusBadge.fromPresentation(presentation: statusPresentation);

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
        // estados usa-se buildJobTimeline (inalterado, partilhado com o
        // lado do worker).
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
            child: _TimelineCard(
              // Horizontal só serve bem o stepper de `open`
              // (_buildOpenStepperSteps: labels curtos — Publicado/
              // Propostas/Escolher/Confirmado). Os restantes ramos usam
              // buildJobTimeline, com labels longos ("Marcado como
              // concluído", "A aguardar confirmação") e subtitle/note por
              // passo (datas, avisos de remarcação) que o horizontal
              // compacto não mostra — mesma razão pela qual
              // client_scheduled_job_detail_screen.dart e
              // worker_my_job_detail_view.dart continuam verticais.
              timeline: job.status == JobStatus.open
                  ? StatusTimelineHorizontal(steps: timelineSteps)
                  : StatusTimeline(steps: timelineSteps),
              supportingLabel:
                  job.status == JobStatus.open ? _openExpiryNotice(job) : null,
              supportingLabelColor: statusPresentation.color.foreground,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: 1,
            child: _ServiceSummaryRow(
              icon: Icons.yard_outlined,
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
              preferredDateLabel: job.preferredDate == null
                  ? 'Flexível'
                  : DateFormat('dd/MM/yyyy').format(job.preferredDate!),
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
          final proposalsButtonLabel = job.proposalCount > 0
              ? 'Ver propostas (${job.proposalCount})'
              : 'Ver propostas';

          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: AppColors.surface,
              surfaceTintColor: AppColors.surface,
              elevation: 0,
              leading: IconButton(
                onPressed: () => context.pop(),
                tooltip: 'Voltar',
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.textPrimary,
                ),
              ),
              title: Text(
                'Pedido #${widget.jobId.substring(0, 8)}',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: AppColors.textPrimary),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: Center(child: statusBadge),
                ),
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
                  'Confirma a conclusão ou relate um problema. Assim que '
                  'confirmares, podes avaliar o profissional.',
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

        if (job.status == JobStatus.completed) {
          detailChildren.add(_workerContactCard(job, workerInfoAsync, theme));
          detailChildren.add(const SizedBox(height: AppSpacing.md));
          detailChildren.add(_buildClientRatingSection(theme, ratingAsync));

          // Direção inversa de _buildClientRatingSection acima (essa é o
          // worker/ajudantes a avaliarem o CLIENTE); este botão abre um ecrã
          // novo para o cliente avaliar o WORKER principal —
          // submit_principal_rating, já usada do lado do worker para avaliar
          // ajudantes, nunca antes chamada a partir do cliente.
          if (workerId.isNotEmpty) {
            bottomBar = BottomActionsBar(children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(
                    '/client/job/${widget.jobId}/rate-worker?workerId=$workerId',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                  icon: const Icon(Icons.star_outline_rounded),
                  label: const Text('Avaliar profissional'),
                ),
              ),
            ]);
          }
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: AppColors.background,
            elevation: 0,
            leading: IconButton(
              onPressed: () => context.pop(),
              tooltip: 'Voltar',
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.textPrimary,
              ),
            ),
            title: Text(
              'Pedido #${widget.jobId.substring(0, 8)}',
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: AppColors.textPrimary),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: Center(child: statusBadge),
              ),
            ],
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
                'Partilha a tua experiência com o prestador e ajudantes.',
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
    final submitted = await showRatingSheet(
      context: context,
      title: 'Avaliar o trabalho',
      subtitle:
          'A nota é partilhada com o prestador e ajudantes. O comentário aparece no perfil do prestador.',
      successMessage:
          'Avaliação enviada! Cobre o prestador e ajudantes deste trabalho.',
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
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

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

/// `expires_at` é o prazo de expiração do PEDIDO INTEIRO (`created_at` +
/// 48h, para `no_response`), não um prazo dedicado a propostas — a frase
/// evita implicar o contrário.
String _openExpiryNotice(JobRequest job) {
  final formatted = DateFormat("dd/MM 'às' HH:mm").format(job.expiresAt);
  return 'Expira a $formatted se não houver nenhuma proposta aceite até lá';
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.timeline,
    required this.supportingLabelColor,
    this.supportingLabel,
  });

  final Widget timeline;
  final String? supportingLabel;

  /// Cor do estado atual (mesmo presenter do badge) — nunca hardcoded a um
  /// único `AppStatusColor`, para respeitar a regra de "mesma cor para
  /// badge + timeline do mesmo estado" mesmo que outro estado além de
  /// `open` venha a preencher `supportingLabel` no futuro.
  final Color supportingLabelColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          timeline,
          if (supportingLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              supportingLabel!,
              textAlign: TextAlign.center,
              style: textTheme.labelMedium?.copyWith(
                color: supportingLabelColor,
              ),
            ),
          ],
        ],
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
    required this.preferredDateLabel,
    required this.urgencyLabel,
    this.sizeLabel,
  });

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
          _MetadataRow(label: 'Data preferida', value: preferredDateLabel),
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
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
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
            maxLines: 1,
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

