import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_initials_avatar.dart';
import '../../../../core/widgets/app_motion.dart';

/// Faixa do pedido direto no detalhe de um pedido aberto (design A5, 3).
/// Só explica quem vê o pedido agora: o estado do pedido continua no badge
/// da AppBar. O enum é só de apresentação; o servidor decide tudo.
/// `onHold` (A7): o jardineiro não pôde ou não respondeu e o cliente
/// desligou "mostrar a outros", por isso o pedido espera pela decisão.
enum DirectRequestWaitingDisplay { waiting, released, onHold }

class DirectRequestWaitingBannerViewData {
  const DirectRequestWaitingBannerViewData({
    required this.display,
    required this.titleLabel,
    required this.descriptionLabel,
    this.workerInitial = '',
    this.workerAvatarUrl,
    this.releaseActionLabel,
    this.cancelActionLabel,
  });

  final DirectRequestWaitingDisplay display;
  final String titleLabel;
  final String descriptionLabel;
  final String workerInitial;
  final String? workerAvatarUrl;

  /// "Mostrar já a todos"; `null` esconde o botão.
  final String? releaseActionLabel;

  /// "Cancelar pedido" no pedido parado; `null` esconde o botão.
  final String? cancelActionLabel;
}

class DirectRequestWaitingBanner extends StatefulWidget {
  const DirectRequestWaitingBanner({
    super.key,
    required this.data,
    required this.onReleaseToAll,
    this.onCancelRequest,
  });

  final DirectRequestWaitingBannerViewData data;

  /// "Cancelar pedido": o ecrã pede confirmação e trata do resto.
  final VoidCallback? onCancelRequest;

  /// Abre o pedido a todos. Devolve `null` em sucesso (o ecrã recarrega o
  /// pedido e a faixa muda sozinha, sem passo otimista) ou a mensagem de
  /// erro, que fica dentro da faixa.
  final Future<String?> Function() onReleaseToAll;

  @override
  State<DirectRequestWaitingBanner> createState() =>
      _DirectRequestWaitingBannerState();
}

class _DirectRequestWaitingBannerState
    extends State<DirectRequestWaitingBanner> {
  bool _submitting = false;
  String? _error;

  @override
  void didUpdateWidget(covariant DirectRequestWaitingBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.display != widget.data.display) {
      _submitting = false;
      _error = null;
    }
  }

  Future<void> _release() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onReleaseToAll();
    } catch (_) {
      error = 'Não foi possível mostrar o pedido a todos. Tenta novamente.';
    }
    // Em sucesso o botão fica bloqueado até o pedido recarregado trocar a
    // faixa (ou a tirar).
    if (!mounted || error == null) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppStaggeredEntrance(
      index: 0,
      child: switch (widget.data.display) {
        DirectRequestWaitingDisplay.waiting ||
        DirectRequestWaitingDisplay.onHold =>
          _WaitingCard(
            data: widget.data,
            submitting: _submitting,
            error: _error,
            onRelease: _release,
            onCancel: widget.onCancelRequest,
          ),
        DirectRequestWaitingDisplay.released =>
          _ReleasedCard(data: widget.data),
      },
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard({
    required this.data,
    required this.submitting,
    required this.error,
    required this.onRelease,
    this.onCancel,
  });

  final DirectRequestWaitingBannerViewData data;
  final bool submitting;
  final String? error;
  final VoidCallback onRelease;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const tone = AppStatusColor.waiting;
    final actionLabel = data.releaseActionLabel;
    final cancelLabel = onCancel == null ? null : data.cancelActionLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppInitialsAvatar(
                initial: data.workerInitial,
                avatarUrl: data.workerAvatarUrl,
                radius: AppSizes.directAvatarRadius,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.titleLabel,
                      style: textTheme.bodyMedium?.copyWith(
                        color: tone.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      data.descriptionLabel,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              height: AppSizes.linkButtonHeight,
              child: OutlinedButton(
                onPressed: submitting ? null : onRelease,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  disabledBackgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.divider),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                  ),
                ),
                child: Text(
                  submitting ? 'A mostrar a todos...' : actionLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    color: submitting
                        ? AppStatusColor.neutral.foreground
                        : AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
          if (cancelLabel != null) ...[
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              width: double.infinity,
              height: AppSizes.linkButtonHeight,
              child: TextButton(
                onPressed: submitting ? null : onCancel,
                child: Text(
                  cancelLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    color: submitting
                        ? AppStatusColor.neutral.foreground
                        : AppStatusColor.cancelled.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              error!,
              style: textTheme.labelMedium?.copyWith(
                color: AppStatusColor.cancelled.foreground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReleasedCard extends StatelessWidget {
  const _ReleasedCard({required this.data});

  final DirectRequestWaitingBannerViewData data;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const tone = AppStatusColor.neutral;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.groups_outlined, color: tone.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.titleLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  data.descriptionLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lugar da faixa enquanto o nome do jardineiro carrega.
class DirectRequestWaitingBannerSkeleton extends StatelessWidget {
  const DirectRequestWaitingBannerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: Container(
        height: AppSizes.directBannerSkeleton,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
    );
  }
}
