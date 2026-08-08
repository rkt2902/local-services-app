import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../proposals/application/proposal_providers.dart';
import '../../worker/application/worker_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../application/job_providers.dart';
import '../data/job_model.dart';

/// Ecrã de celebração mostrado logo depois de o cliente aceitar uma
/// proposta — substitui o antigo "snackbar + navega para /client/jobs".
///
/// Não recebe dados pré-resolvidos por navegação (evita `extra` com objetos
/// complexos, ver decisions_log.md A2) — resolve tudo aqui via providers já
/// existentes (mesmos usados em client_job_detail_screen.dart).
class ClientJobConfirmedScreen extends ConsumerWidget {
  const ClientJobConfirmedScreen({
    super.key,
    required this.jobId,
    required this.workerId,
  });

  final String jobId;
  final String workerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobAsync = ref.watch(jobByIdProvider(jobId));
    final proposalAsync = ref.watch(acceptedProposalForJobProvider(jobId));
    final workerInfoAsync = ref.watch(workerBasicInfoProvider(workerId));
    final serviceTypesAsync = ref.watch(serviceTypesProvider);
    final ratingAsync = ref.watch(ratingSummaryProvider(workerId));

    final loading = jobAsync.isLoading ||
        proposalAsync.isLoading ||
        workerInfoAsync.isLoading ||
        serviceTypesAsync.isLoading;

    if (loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final job = jobAsync.asData?.value;
    if (job == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text(
            jobAsync.hasError
                ? friendlyError(jobAsync.error!)
                : 'Pedido não encontrado.',
          ),
        ),
      );
    }

    final proposal = proposalAsync.asData?.value;
    final workerInfo = workerInfoAsync.asData?.value ?? const {};
    final serviceTypes = serviceTypesAsync.asData?.value ?? const [];
    final rating = ratingAsync.asData?.value;

    final serviceLabel = serviceTypes
            .where((s) => s.id == job.serviceTypeId)
            .map((s) => s.name)
            .firstOrNull ??
        '—';
    final workerName = workerInfo['full_name'] ?? '';
    final workerAvatarUrl = workerInfo['avatar_url'];
    final workerPhone = workerInfo['phone'] ?? '';

    final priceLabel = proposal != null && proposal.hourlyRate > 0
        ? '${proposal.hourlyRate.toStringAsFixed(2)} €/hora'
        : 'Preço a definir';

    return _ClientJobConfirmedView(
      workerName: workerName.isEmpty ? '—' : workerName,
      workerAvatarUrl:
          (workerAvatarUrl != null && workerAvatarUrl.isNotEmpty)
              ? workerAvatarUrl
              : null,
      workerRatingLabel:
          rating != null && rating.ratingCount > 0
              ? rating.avgRating.toStringAsFixed(1)
              : '—',
      workerReviewsLabel: rating != null
          ? '${rating.ratingCount} '
              '${rating.ratingCount == 1 ? 'avaliação' : 'avaliações'}'
          : '0 avaliações',
      dateTimeLabel: _confirmedScheduleLabel(job),
      serviceLabel: serviceLabel,
      addressLabel: job.addressText.isNotEmpty
          ? job.addressText
          : 'Localização não especificada',
      priceLabel: priceLabel,
      onCallPressed: workerPhone.isEmpty
          ? null
          : () => _openWhatsApp(workerPhone),
      onWorkerPressed: () {
        // Sem ecrã de perfil público do worker no cliente hoje — sem-op
        // seguro em vez de navegar para um sítio que não existe.
      },
      onViewJobPressed: () {
        GoRouter.of(context).pushReplacement('/client/job/$jobId');
      },
    );
  }

  Future<void> _openWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _confirmedScheduleLabel(JobRequest job) {
    if (job.confirmedDate == null) return 'Data a combinar';
    final date = DateFormat('dd/MM/yyyy').format(job.confirmedDate!);
    if (job.confirmedFlexible) return '$date (horário flexível)';
    if (job.confirmedTime != null) return '$date às ${job.confirmedTime}';
    return date;
  }
}

class _ClientJobConfirmedView extends StatelessWidget {
  const _ClientJobConfirmedView({
    required this.workerName,
    required this.workerAvatarUrl,
    required this.workerRatingLabel,
    required this.workerReviewsLabel,
    required this.dateTimeLabel,
    required this.serviceLabel,
    required this.addressLabel,
    required this.priceLabel,
    required this.onCallPressed,
    required this.onWorkerPressed,
    required this.onViewJobPressed,
  });

  final String workerName;
  final String? workerAvatarUrl;
  final String workerRatingLabel;
  final String workerReviewsLabel;

  final String dateTimeLabel;
  final String serviceLabel;
  final String addressLabel;
  final String priceLabel;

  final VoidCallback? onCallPressed;
  final VoidCallback onWorkerPressed;
  final VoidCallback onViewJobPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final avatarImage =
        workerAvatarUrl != null ? NetworkImage(workerAvatarUrl!) : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                color: AppColors.primary,
                child: Column(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surface.withValues(alpha: 0.20),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 32,
                        color: AppColors.surface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Pedido confirmado!',
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        color: AppColors.surface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Estamos à disposição.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.surface,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                child: Column(
                  children: [
                    AppStaggeredEntrance(
                      index: 0,
                      child: InkWell(
                        onTap: onWorkerPressed,
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: AppColors.primaryContainer,
                              backgroundImage: avatarImage,
                              child: avatarImage == null
                                  ? const Icon(
                                      Icons.person_outline_rounded,
                                      color: AppColors.primary,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    workerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.titleMedium?.copyWith(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    '★ $workerRatingLabel ($workerReviewsLabel)',
                                    style: textTheme.labelMedium?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 1,
                      child: _ContactButton(
                        icon: Icons.chat_outlined,
                        label: 'Contactar via WhatsApp',
                        onPressed: onCallPressed,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 2,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Column(
                          children: [
                            _DetailRow(label: 'Data e hora', value: dateTimeLabel),
                            const SizedBox(height: AppSpacing.sm),
                            _DetailRow(label: 'Serviço', value: serviceLabel),
                            const SizedBox(height: AppSpacing.sm),
                            _DetailRow(label: 'Morada', value: addressLabel),
                            const SizedBox(height: AppSpacing.md),
                            const Divider(height: 1, color: AppColors.divider),
                            const SizedBox(height: AppSpacing.md),
                            _DetailRow(
                              label: 'Valor acordado',
                              value: priceLabel,
                              highlighted: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 3,
                      child: PrimaryActionButton(
                        label: 'Ver detalhe do pedido',
                        onPressed: onViewJobPressed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  const _ContactButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primaryContainer,
          foregroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.divider,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          textStyle: textTheme.labelMedium,
        ),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

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
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: textTheme.bodyMedium?.copyWith(
              color: highlighted ? AppColors.primary : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
