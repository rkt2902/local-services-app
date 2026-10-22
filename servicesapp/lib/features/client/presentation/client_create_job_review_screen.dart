import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/picked_photo.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_step_progress.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../../core/widgets/service_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/application/direct_request_labels.dart';
import '../application/client_create_job_wizard_provider.dart';
import 'widgets/direct_request_review_banner.dart';
import '../../../core/widgets/app_toast.dart';

/// Passo 4/4 de "Criar pedido" — rever o draft e publicar.
///
/// Ao contrário dos passos 1-3 (que só escrevem no wizard provider), este
/// ecrã é quem de facto publica: chama `createJob`, faz upload das fotos,
/// invalida providers e navega para a home. O passo 3 deixou de publicar
/// diretamente — só guarda descrição/fotos e avança para aqui.
///
/// Baseado no mockup em `doc.txt` (secção "1a. Criar pedido — Passo 4"),
/// adaptado para ler o wizard provider diretamente em vez de receber
/// view-data/callbacks injetados — mesmo padrão dos outros 3 ecrãs do
/// wizard, nenhum dos quais usa wrapper+view separados.
class ClientCreateJobReviewScreen extends ConsumerStatefulWidget {
  const ClientCreateJobReviewScreen({super.key});

  @override
  ConsumerState<ClientCreateJobReviewScreen> createState() =>
      _ClientCreateJobReviewScreenState();
}

class _ClientCreateJobReviewScreenState
    extends ConsumerState<ClientCreateJobReviewScreen> {
  bool _publishing = false;
  bool _successVisible = false;
  Timer? _successTimer;

  /// `true` depois de o pedido ser criado: não se publica duas vezes.
  bool _published = false;

  bool get _interactionEnabled => !_publishing && !_published;

  /// Limpeza depois de o pedido existir (invalidar a lista e limpar o
  /// rascunho). Se o ecrã sair antes do temporizador de sucesso, corre na
  /// mesma, fora do dispose.
  VoidCallback? _pendingCleanup;

  @override
  void dispose() {
    final pending = _successTimer;
    final cleanup = _pendingCleanup;
    if (pending != null && pending.isActive && cleanup != null) {
      pending.cancel();
      Future.microtask(cleanup);
    }
    super.dispose();
  }

  void _editService() {
    context.push('/client/create-job?fromReview=true');
  }

  void _editScheduling() {
    context.push('/client/create-job/schedule?fromReview=true');
  }

  void _editDescriptionAndPhotos() {
    context.push('/client/create-job/description?fromReview=true');
  }

  Future<void> _publish() async {
    if (_publishing || _published) return;
    FocusScope.of(context).unfocus();

    final wizard = ref.read(clientCreateJobWizardProvider);
    if (wizard.serviceTypeId == null ||
        wizard.locationLat == null ||
        wizard.locationLng == null) {
      AppToast.of(context).error('Falta informação dos passos anteriores. Volta atrás e confirma.');
      return;
    }

    setState(() {
      _publishing = true;
      _successVisible = false;
    });
    final toast = AppToast.of(context);
    final router = GoRouter.of(context);
    // Capturados antes dos awaits: o ecrã pode já não existir quando o
    // temporizador de sucesso disparar (ex.: o utilizador voltou atrás).
    final container = ProviderScope.containerOf(context, listen: false);
    final wizardNotifier = ref.read(clientCreateJobWizardProvider.notifier);

    final String jobId;
    try {
      final user = ref.read(currentUserProvider)!;
      final repo = ref.read(jobRepositoryProvider);

      jobId = await repo.createJob(
        clientId: user.id,
        serviceTypeId: wizard.serviceTypeId!,
        addressText: wizard.addressText,
        locationArea: wizard.locationArea,
        locationLat: wizard.locationLat!,
        locationLng: wizard.locationLng!,
        dateMode: wizard.dateMode,
        preferredDate: wizard.dateMode == DateMode.fixed
            ? wizard.preferredDate
            : null,
        availabilityText: wizard.dateMode == DateMode.availability
            ? wizard.availabilityText.trim()
            : null,
        urgency: wizard.urgency,
        sizeEstimate: wizard.sizeEstimate,
        description: wizard.description.trim(),
        directSourceJobId: wizard.directSourceJobId,
      );
    } catch (e) {
      // O pedido não foi criado: pode repetir-se sem risco de duplicar.
      if (!mounted) return;
      setState(() => _publishing = false);
      toast.error(friendlyError(e));
      return;
    }

    _published = true;
    void cleanup() {
      container.invalidate(clientJobsProvider);
      wizardNotifier.reset();
    }

    _pendingCleanup = cleanup;

    // A partir daqui o pedido JÁ existe. Uma falha nas fotos não pode
    // devolver o utilizador ao botão "Publicar" (repetir criava um pedido
    // duplicado): segue para o pedido com um aviso.
    // Upload só acontece agora, no momento real de publicar — as fotos
    // até aqui são só `XFile` locais guardadas no wizard provider.
    var failedPhotos = 0;
    final user = ref.read(currentUserProvider);
    final repo = ref.read(jobRepositoryProvider);
    for (final photo in wizard.photos) {
      try {
        await repo.uploadJobPhoto(jobId: jobId, clientId: user!.id, file: photo);
      } catch (_) {
        failedPhotos++;
      }
    }

    void finish() {
      // T4: navegar → SnackBar → invalidar (e limpar o rascunho, que este
      // ecrã observa).
      if (failedPhotos > 0) {
        router.go('/client/job/$jobId');
        toast.error(failedPhotos == 1
              ? 'Pedido publicado, mas não foi possível enviar 1 foto.'
              : 'Pedido publicado, mas não foi possível enviar $failedPhotos fotos.');
      } else {
        router.go('/client/home');
      }
      cleanup();
    }

    if (!mounted) {
      // Saiu durante o upload: só limpa, sem navegar a partir de um ecrã
      // que já não existe.
      cleanup();
      return;
    }
    if (failedPhotos > 0) {
      finish();
      return;
    }

    setState(() {
      _publishing = false;
      _successVisible = true;
    });

    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _successTimer?.cancel();
    _successTimer = Timer(
      disableAnimations ? Duration.zero : const Duration(milliseconds: 1100),
      finish,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final wizard = ref.watch(clientCreateJobWizardProvider);
    final serviceTypesAsync = ref.watch(serviceTypesProvider);

    final selectedServiceType = serviceTypesAsync.asData?.value
        .where((s) => s.id == wizard.serviceTypeId)
        .firstOrNull;
    final serviceLabel = selectedServiceType?.name ?? 'Serviço selecionado';

    final baseWhenLabel = jobDeadlineLabel(
      wizard.dateMode,
      wizard.preferredDate,
      availabilityText: wizard.availabilityText,
    );
    final whenLabel = wizard.urgency == Urgency.urgent
        ? 'Urgente · $baseWhenLabel'
        : baseWhenLabel;

    final sizeLabel = wizard.sizeEstimate?.label ?? '—';

    final addressLabel =
        wizard.addressText.isEmpty ? 'Localização no mapa' : wizard.addressText;

    final photos = wizard.photos.map<ImageProvider>(pickedPhotoImage).toList();

    // "Pedir de novo" (0057): o prazo de 24 horas é o do servidor; aqui só
    // se explica.
    final directName = firstNameOr(wizard.directWorkerName, 'o jardineiro');
    final directBanner = wizard.isDirectRequest
        ? DirectRequestReviewBannerViewData(
            titleLabel: 'Vai primeiro para $directName',
            descriptionLabel:
                'Durante 24 horas, só $directName vê o pedido e pode enviar '
                'proposta. Se não responder, mostramos o pedido a todos os '
                'jardineiros.',
            workerInitial: initialOf(
              wizard.directWorkerName.isEmpty
                  ? 'Jardineiro'
                  : wizard.directWorkerName,
            ),
            workerAvatarUrl: wizard.directWorkerAvatarUrl,
          )
        : null;
    final overflowCount = photos.length - 2;
    final photosOverflowLabel = overflowCount > 0 ? '+$overflowCount' : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: _interactionEnabled
              ? () => goBackOr(context, '/client/create-job/description')
              : null,
          tooltip: 'Voltar',
          icon: Icon(
            Icons.arrow_back_rounded,
            color: _interactionEnabled
                ? AppColors.textPrimary
                : AppStatusColor.neutral.foreground,
          ),
        ),
        titleSpacing: 0,
        title: Text(
          'Criar pedido',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: IgnorePointer(
                  ignoring: !_interactionEnabled,
                  child: const AppStepProgress(currentStep: 4, totalSteps: 4),
                ),
              ),
              Expanded(
                child: IgnorePointer(
                  ignoring: !_interactionEnabled,
                  child: ListView(
                    // Top = AppSpacing.md (era 0) — os outros 3 passos do
                    // wizard (serviço/agendamento/descrição) têm sempre esta
                    // margem entre a barra de progresso e o primeiro item;
                    // só a revisão estava colada, sem respiro.
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    children: [
                      AppStaggeredEntrance(
                        index: 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Revê o teu pedido',
                              style: textTheme.titleMedium?.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              'Confirma os detalhes antes de publicar.',
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (directBanner != null) ...[
                        DirectRequestReviewBanner(
                          data: directBanner,
                          entranceIndex: 1,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      AppStaggeredEntrance(
                        index: 1,
                        child: _ServiceCard(
                          serviceLabel: serviceLabel,
                          icon: serviceIconFor(selectedServiceType?.icon),
                          onEdit: _editService,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppStaggeredEntrance(
                        index: 2,
                        child: _SchedulingCard(
                          whenLabel: whenLabel,
                          sizeLabel: sizeLabel,
                          addressLabel: addressLabel,
                          onEdit: _editScheduling,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppStaggeredEntrance(
                        index: 3,
                        child: _DescriptionPhotosCard(
                          description: wizard.description,
                          photos: photos,
                          photosOverflowLabel: photosOverflowLabel,
                          onEdit: _editDescriptionAndPhotos,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: PrimaryActionButton(
                  label: _publishing ? 'A publicar...' : 'Publicar pedido',
                  isLoading: _publishing,
                  onPressed: _publishing ? null : _publish,
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: AppSuccessFeedback(
              visible: _successVisible,
              message: 'Pedido publicado com sucesso.',
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.title,
    required this.onEdit,
    required this.child,
  });

  final String title;
  final VoidCallback onEdit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Editar',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.serviceLabel,
    required this.icon,
    required this.onEdit,
  });

  final String serviceLabel;
  final IconData icon;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return _ReviewCard(
      title: 'Serviço',
      onEdit: onEdit,
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
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              serviceLabel,
              style: textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SchedulingCard extends StatelessWidget {
  const _SchedulingCard({
    required this.whenLabel,
    required this.sizeLabel,
    required this.addressLabel,
    required this.onEdit,
  });

  final String whenLabel;
  final String sizeLabel;
  final String addressLabel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return _ReviewCard(
      title: 'Agendamento',
      onEdit: onEdit,
      child: Column(
        children: [
          _SummaryRow(label: 'Quando', value: whenLabel, valueMaxLines: 3),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(label: 'Dimensão', value: sizeLabel, valueMaxLines: 2),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(label: 'Morada', value: addressLabel, valueMaxLines: 3),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
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
        const SizedBox(width: AppSpacing.md),
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

class _DescriptionPhotosCard extends StatelessWidget {
  const _DescriptionPhotosCard({
    required this.description,
    required this.photos,
    required this.photosOverflowLabel,
    required this.onEdit,
  });

  final String description;
  final List<ImageProvider> photos;
  final String? photosOverflowLabel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return _ReviewCard(
      title: 'Descrição e fotos',
      onEdit: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (photos.isEmpty)
            Text(
              'Sem fotos adicionadas',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            _PhotosPreview(photos: photos, overflowLabel: photosOverflowLabel),
        ],
      ),
    );
  }
}

class _PhotosPreview extends StatelessWidget {
  const _PhotosPreview({required this.photos, required this.overflowLabel});

  final List<ImageProvider> photos;
  final String? overflowLabel;

  @override
  Widget build(BuildContext context) {
    final visiblePhotos = photos.take(2).toList();

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        ...visiblePhotos.map(
          (photo) => ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.input),
            child: Image(image: photo, width: 64, height: 64, fit: BoxFit.cover),
          ),
        ),
        if (overflowLabel != null) _PhotoOverflow(label: overflowLabel!),
      ],
    );
  }
}

class _PhotoOverflow extends StatelessWidget {
  const _PhotoOverflow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppStatusColor.neutral.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: textTheme.bodyMedium?.copyWith(
          color: AppStatusColor.neutral.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
