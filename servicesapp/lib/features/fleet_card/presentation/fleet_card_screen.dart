import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/enums.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_status_presenters.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/fleet_card_providers.dart';
import '../data/fleet_card_model.dart';

/// Rota `/worker/fleet-card` — ecrã único que se ramifica pelo estado
/// atual (última linha de `worker_fleet_cards`, ver
/// `FleetCardRepository.fetchMyFleetCard`): sem pedido, pendente, ativo
/// ou rejeitado. Nenhum destes 3 últimos estados tem mockup — seguem o
/// design system já estabelecido (mesmos tokens/motion dos outros ecrãs).
class FleetCardScreen extends ConsumerWidget {
  const FleetCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardAsync = ref.watch(myFleetCardProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: cardAsync.when(
          loading: () => const _FleetCardLoading(),
          error: (e, _) => _FleetCardError(
            message: friendlyError(e),
            onRetry: () => ref.invalidate(myFleetCardProvider),
          ),
          data: (card) {
            if (card == null) return const _NoCardView();
            return switch (card.status) {
              FleetCardStatus.pending => const _PendingCardView(),
              FleetCardStatus.rejected => const _RejectedCardView(),
              FleetCardStatus.active => _ActiveCardView(card: card),
              // Inatingível na prática: `card` não-nulo nunca produz
              // `notRequested` (só existe para null — ver
              // FleetCardStatus.fromValue). Mantido só por exaustividade.
              FleetCardStatus.notRequested => const _NoCardView(),
            };
          },
        ),
      ),
    );
  }
}

class _FleetHeader extends StatelessWidget {
  const _FleetHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
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
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            'Cartão frota',
            style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

// ─── Sem pedido ────────────────────────────────────────────────────────

class _NoCardView extends StatelessWidget {
  const _NoCardView();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        _FleetHeader(onBack: () => context.pop()),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppStaggeredEntrance(
                  index: 0,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.local_gas_station_outlined,
                      color: AppColors.primary,
                      size: 46,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 1,
                  child: Text(
                    'Adicionar cartão frota',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppStaggeredEntrance(
                  index: 2,
                  child: Text(
                    'Adiciona o teu cartão frota para teres desconto no combustível.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppStaggeredEntrance(
                  index: 3,
                  child: PrimaryActionButton(
                    label: 'Adicionar cartão',
                    onPressed: () => context.push('/worker/fleet-card/scan'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Pendente ────────────────────────────────────────────────────────────

class _PendingCardView extends StatelessWidget {
  const _PendingCardView();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        _FleetHeader(onBack: () => context.pop()),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppStaggeredEntrance(
                  index: 0,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: FleetCardStatus.pending.presentation.color.background,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.hourglass_top_outlined,
                      color: FleetCardStatus.pending.presentation.color.foreground,
                      size: 46,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 1,
                  child: AppStatusBadge.fromPresentation(
                    presentation: FleetCardStatus.pending.presentation,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppStaggeredEntrance(
                  index: 2,
                  child: Text(
                    'O teu pedido está a ser analisado',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppStaggeredEntrance(
                  index: 3,
                  child: Text(
                    'Assim que confirmarmos os dados do teu cartão, ele fica '
                    'disponível aqui para usares na bomba de combustível.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Rejeitado ───────────────────────────────────────────────────────────

class _RejectedCardView extends StatelessWidget {
  const _RejectedCardView();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        _FleetHeader(onBack: () => context.pop()),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppStaggeredEntrance(
                  index: 0,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: FleetCardStatus.rejected.presentation.color.background,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.error_outline_rounded,
                      color: FleetCardStatus.rejected.presentation.color.foreground,
                      size: 46,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppStaggeredEntrance(
                  index: 1,
                  child: AppStatusBadge.fromPresentation(
                    presentation: FleetCardStatus.rejected.presentation,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppStaggeredEntrance(
                  index: 2,
                  child: Text(
                    'Não foi possível validar o teu cartão',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppStaggeredEntrance(
                  index: 3,
                  child: Text(
                    'Confirma que a foto está legível e que os dados '
                    'correspondem a um cartão frota válido, e tenta outra vez.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppStaggeredEntrance(
                  index: 4,
                  child: PrimaryActionButton(
                    label: 'Tentar novamente',
                    onPressed: () => context.push('/worker/fleet-card/scan'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Ativo ───────────────────────────────────────────────────────────────

class _ActiveCardView extends StatelessWidget {
  const _ActiveCardView({required this.card});

  final FleetCard card;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FleetHeader(onBack: () => context.pop()),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              AppStaggeredEntrance(index: 0, child: _DigitalFleetCard(card: card)),
              const SizedBox(height: AppSpacing.sm),
              AppStaggeredEntrance(index: 1, child: _BarcodeCard(card: card)),
              const SizedBox(height: AppSpacing.sm),
              AppStaggeredEntrance(
                index: 2,
                child: _ReplaceCardAction(
                  onTap: () => context.push('/worker/fleet-card/scan'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DigitalFleetCard extends StatelessWidget {
  const _DigitalFleetCard({required this.card});

  final FleetCard card;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subtitleParts = [
      if (card.holderName != null && card.holderName!.isNotEmpty) card.holderName!,
      if (card.cardNumber != null && card.cardNumber!.isNotEmpty) 'nº ${card.cardNumber}',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(
              Icons.local_gas_station_outlined,
              size: 70,
              color: AppColors.accent,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'CARTÃO FROTA',
                      style: textTheme.labelMedium?.copyWith(color: AppColors.surface),
                    ),
                  ),
                  AppStatusBadge.fromPresentation(presentation: card.status.presentation),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                card.barcodeValue,
                style: textTheme.titleLarge?.copyWith(color: AppColors.surface),
              ),
              if (subtitleParts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitleParts.join(' · '),
                  style: textTheme.labelMedium?.copyWith(color: AppColors.surface),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BarcodeCard extends StatelessWidget {
  const _BarcodeCard({required this.card});

  final FleetCard card;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Text(
            'MOSTRE NA GASOLINEIRA',
            style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          // qr_flutter — já usado no cartão partilhável do worker
          // (_showQrDialog em worker_profile_screen.dart). Sem pacote de
          // código de barras 1D: o código de barras real do cartão físico
          // é substituído por um QR que codifica o mesmo número — a
          // gasolineira real (quando existir parceria) provavelmente vai
          // querer 1D, não QR; sinalizado no relatório.
          QrImageView(
            data: card.barcodeValue,
            size: 180,
            backgroundColor: AppColors.surface,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            card.barcodeValue,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _ReplaceCardAction extends StatelessWidget {
  const _ReplaceCardAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.sync_rounded, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Substituir cartão',
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Loading / erro ────────────────────────────────────────────────────

class _FleetCardLoading extends StatelessWidget {
  const _FleetCardLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(color: AppColors.primary));
  }
}

class _FleetCardError extends StatelessWidget {
  const _FleetCardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Tentar novamente',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
