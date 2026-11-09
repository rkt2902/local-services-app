import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/worker_public_card_feature_access.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/utils/price_labels.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_initials_avatar.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_plan_badge.dart';
import '../../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../../core/widgets/bottom_actions_bar.dart';
import '../../../../core/widgets/primary_action_button.dart';
import '../../data/worker_public_card_model.dart';
import 'worker_showcase_section.dart';

/// Quem está a ver o cartão público `/w/:id` (A7). Muda só o rodapé: um
/// jardineiro a ver o cartão de outro não é um papel novo.
enum WorkerPublicCardViewerMode {
  clientSignedIn,
  signedOut,
  anotherWorker,
  ownerPreview,
}

class WorkerPublicCardViewData {
  const WorkerPublicCardViewData({
    required this.card,
    required this.featureAccess,
    required this.viewerMode,
    required this.directRequestActionLabel,
    this.latestReviewLabel,
  });

  final WorkerPublicCard card;
  final WorkerPublicCardFeatureAccess featureAccess;
  final WorkerPublicCardViewerMode viewerMode;

  /// "Pedir orçamento a Rui".
  final String directRequestActionLabel;

  /// Avaliação recente com 4 ou 5 estrelas; `null` esconde a secção.
  final String? latestReviewLabel;
}

/// Cartão público do jardineiro, sem Riverpod nem navegação: o ecrã
/// (`WorkerPublicProfileScreen`) resolve quem está a ver e o que o cartão
/// deixa fazer, e trata dos toques.
///
/// `data` `null` = o cartão não existe; com `canUsePublicCard` desligado
/// fica igual ("Este cartão já não está disponível").
class WorkerPublicCardView extends StatelessWidget {
  const WorkerPublicCardView({
    super.key,
    required this.dataAsync,
    required this.onBack,
    required this.onStartDirectRequest,
    required this.onShareCard,
    required this.onLogin,
    this.onCreateGenericRequest,
    this.onRetry,
    this.onRatingsPressed,
  });

  final AsyncValue<WorkerPublicCardViewData?> dataAsync;
  final VoidCallback onBack;
  final ValueChanged<String> onStartDirectRequest;
  final ValueChanged<String> onShareCard;
  final VoidCallback onLogin;

  /// "Criar pedido para todos" no cartão indisponível; `null` esconde.
  final VoidCallback? onCreateGenericRequest;
  final VoidCallback? onRetry;

  /// Lista de avaliações (só com sessão: RLS de ratings); `null` deixa a
  /// média sem toque.
  final VoidCallback? onRatingsPressed;

  @override
  Widget build(BuildContext context) {
    final data = dataAsync.asData?.value;
    final available = data != null && data.featureAccess.canUsePublicCard;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: onBack,
          tooltip: 'Voltar',
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      bottomNavigationBar: available
          ? _PublicCardFooter(
              data: data,
              onStartDirectRequest: onStartDirectRequest,
              onShareCard: onShareCard,
              onLogin: onLogin,
            )
          : null,
      body: dataAsync.when(
        loading: () => const AppScreenLoadingSkeleton(),
        error: (_, _) => _CenteredState(
          child: AppEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Não foi possível abrir o cartão',
            message: 'Verifica a ligação e tenta novamente.',
            actionLabel: onRetry == null ? null : 'Tentar novamente',
            onAction: onRetry,
            tone: AppStatusColor.cancelled,
          ),
        ),
        data: (data) {
          if (data == null || !data.featureAccess.canUsePublicCard) {
            final onCreate = onCreateGenericRequest;
            return _CenteredState(
              child: AppEmptyState(
                icon: Icons.person_off_outlined,
                title: 'Este cartão já não está disponível',
                message: 'Este jardineiro já não tem um cartão público ativo.',
                actionLabel: onCreate == null ? null : 'Criar pedido para todos',
                onAction: onCreate,
                tone: AppStatusColor.neutral,
              ),
            );
          }
          return _PublicCardBody(
            data: data,
            onRatingsPressed: onRatingsPressed,
          );
        },
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}

class _PublicCardBody extends StatelessWidget {
  const _PublicCardBody({required this.data, this.onRatingsPressed});

  final WorkerPublicCardViewData data;
  final VoidCallback? onRatingsPressed;

  @override
  Widget build(BuildContext context) {
    final card = data.card;
    final textTheme = Theme.of(context).textTheme;
    final hasRatings = card.ratingCount > 0;
    final ratingStyle =
        textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary);
    final ratingRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.star_rounded,
          size: AppSizes.inlineIcon,
          color: AppColors.logoAccent,
        ),
        const SizedBox(width: AppSpacing.xxs),
        if (hasRatings) ...[
          Text(
            decimalLabel(card.avgRating, 1),
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            ' · ${card.ratingCount} '
            'avalia${card.ratingCount == 1 ? 'ção' : 'ções'}',
            style: ratingStyle,
          ),
        ] else
          Text('Sem avaliações ainda', style: ratingStyle),
      ],
    );
    final onRatings = hasRatings ? onRatingsPressed : null;
    final planTier = card.planTier;
    final review = data.latestReviewLabel;
    final isOwner = data.viewerMode == WorkerPublicCardViewerMode.ownerPreview;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isOwner) ...[
            const AppStaggeredEntrance(index: 0, child: _OwnerPreviewNotice()),
            const SizedBox(height: AppSpacing.md),
          ],
          AppStaggeredEntrance(
            index: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: AppInitialsAvatar(
                  initial: nameInitials(card.fullName),
                  avatarUrl: card.avatarUrl,
                  radius: AppSizes.publicAvatar / 2,
                  textStyle: textTheme.titleLarge,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppStaggeredEntrance(
            index: 1,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        card.fullName,
                        textAlign: TextAlign.center,
                        style: textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (planTier.isPaid) ...[
                      const SizedBox(width: AppSpacing.xs),
                      AppPlanBadge(tier: planTier, large: true),
                    ],
                  ],
                ),
                // Só a zona: o raio fica de fora do cartão público
                // (worker_public_card, 0033).
                if (card.locationName.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    card.locationName,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: AppSpacing.xxs),
                if (onRatings != null)
                  InkWell(
                    onTap: onRatings,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: ratingRow,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    child: ratingRow,
                  ),
              ],
            ),
          ),
          if (card.serviceNames.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            AppStaggeredEntrance(
              index: 2,
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: card.serviceNames
                    .map((name) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            name,
                            style: textTheme.labelMedium
                                ?.copyWith(color: AppColors.primary),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: 3,
            child: WorkerShowcaseSection(
              bio: card.bio,
              highlights: card.highlights,
              socialLinks: card.socialLinks,
            ),
          ),
          if (review != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppStaggeredEntrance(
              index: 4,
              child: _LatestReview(label: review),
            ),
          ],
        ],
      ),
    );
  }
}

/// "RS" para "Rui Santos", "R" para "Rui".
String nameInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  String first(String part) =>
      String.fromCharCode(part.runes.first).toUpperCase();
  if (parts.length == 1) return first(parts.first);
  return '${first(parts.first)}${first(parts.last)}';
}

class _OwnerPreviewNotice extends StatelessWidget {
  const _OwnerPreviewNotice();

  @override
  Widget build(BuildContext context) {
    const tone = AppStatusColor.info;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, color: tone.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Pré-visualização. É assim que os clientes veem o teu cartão.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LatestReview extends StatelessWidget {
  const _LatestReview({required this.label});

  final String label;

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
          Text(
            'AVALIAÇÃO RECENTE',
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rodapé por tipo de visitante. Sem nada para fazer (outro jardineiro, ou
/// a capacidade desligada) não há barra nenhuma.
class _PublicCardFooter extends StatelessWidget {
  const _PublicCardFooter({
    required this.data,
    required this.onStartDirectRequest,
    required this.onShareCard,
    required this.onLogin,
  });

  final WorkerPublicCardViewData data;
  final ValueChanged<String> onStartDirectRequest;
  final ValueChanged<String> onShareCard;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final access = data.featureAccess;
    final workerId = data.card.workerId;
    final textTheme = Theme.of(context).textTheme;

    final children = switch (data.viewerMode) {
      WorkerPublicCardViewerMode.clientSignedIn
          when access.canReceiveDirectRequests =>
        [
          PrimaryActionButton(
            label: data.directRequestActionLabel,
            onPressed: () => onStartDirectRequest(workerId),
          ),
        ],
      WorkerPublicCardViewerMode.signedOut
          when access.canReceiveDirectRequests =>
        [
          PrimaryActionButton(
            label: data.directRequestActionLabel,
            onPressed: () => onStartDirectRequest(workerId),
          ),
          const SizedBox(height: AppSpacing.xxs),
          TextButton(
            onPressed: onLogin,
            child: Text(
              'Já tens conta? Entra',
              style: textTheme.labelMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      WorkerPublicCardViewerMode.ownerPreview
          when access.canSharePublicCard =>
        [
          PrimaryActionButton(
            label: 'Partilhar cartão',
            onPressed: () => onShareCard(workerId),
          ),
        ],
      _ => const <Widget>[],
    };
    if (children.isEmpty) return const SizedBox.shrink();

    return ColoredBox(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: BottomActionsBar(children: children),
      ),
    );
  }
}
