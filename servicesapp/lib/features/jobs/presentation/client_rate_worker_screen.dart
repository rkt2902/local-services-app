import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../ratings/application/rating_providers.dart';
import '../../worker/application/worker_providers.dart';

/// Ecrã novo — cliente avalia o worker principal (direção inversa de
/// `_buildClientRatingSection`/`_showClientRatingSheet` em
/// client_job_detail_screen.dart, que é o worker/ajudantes a avaliarem o
/// cliente). RPC `submit_principal_rating`, já usada do lado do worker
/// para avaliar ajudantes — nunca antes chamada a partir do cliente.
class ClientRateWorkerScreen extends ConsumerStatefulWidget {
  const ClientRateWorkerScreen({
    super.key,
    required this.jobId,
    required this.workerId,
  });

  final String jobId;
  final String workerId;

  @override
  ConsumerState<ClientRateWorkerScreen> createState() {
    return _ClientRateWorkerScreenState();
  }
}

class _ClientRateWorkerScreenState
    extends ConsumerState<ClientRateWorkerScreen> {
  int _rating = 0;
  final _commentController = TextEditingController();

  bool _submitting = false;
  bool _showSuccessFeedback = false;
  Timer? _successTimer;

  String _ratingLabel() {
    switch (_rating) {
      case 1:
        return 'Muito fraco';
      case 2:
        return 'Fraco';
      case 3:
        return 'Bom';
      case 4:
        return 'Muito bom!';
      case 5:
        return 'Excelente!';
      default:
        return '';
    }
  }

  Future<void> _submit() async {
    if (_rating <= 0 || _submitting) return;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(ratingRepositoryProvider).submitPrincipalRating(
            jobId: widget.jobId,
            rateeId: widget.workerId,
            stars: _rating,
            comment: _commentController.text.trim().isEmpty
                ? null
                : _commentController.text.trim(),
          );
      ref.invalidate(myRatingForJobAndRateeProvider((widget.jobId, widget.workerId)));

      if (!mounted) return;
      setState(() {
        _submitting = false;
        _showSuccessFeedback = true;
      });

      final disableAnimations =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      _successTimer?.cancel();
      _successTimer = Timer(
        disableAnimations ? Duration.zero : const Duration(milliseconds: 1100),
        () {
          if (!mounted) return;
          GoRouter.of(context).pop();
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final workerInfoAsync = ref.watch(workerBasicInfoProvider(widget.workerId));
    final workerInfo = workerInfoAsync.asData?.value ?? const {};
    final workerName = workerInfo['full_name'] ?? '';
    final avatarUrl = workerInfo['avatar_url'];
    final avatarImage =
        (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null;

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
        titleSpacing: 0,
        title: Text(
          'Avaliar',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    children: [
                      AppStaggeredEntrance(
                        index: 0,
                        child: CircleAvatar(
                          radius: 38,
                          backgroundColor: AppColors.primaryContainer,
                          backgroundImage: avatarImage,
                          child: avatarImage == null
                              ? const Icon(
                                  Icons.person_outline_rounded,
                                  size: 36,
                                  color: AppColors.primary,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppStaggeredEntrance(
                        index: 1,
                        child: Text(
                          'Avaliar ${workerName.isEmpty ? 'o prestador' : workerName}',
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Como foi a sua experiência?',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppStaggeredEntrance(
                        index: 2,
                        child: _RatingStars(
                          rating: _rating,
                          onChanged: (rating) => setState(() => _rating = rating),
                        ),
                      ),
                      AnimatedSize(
                        duration:
                            MediaQuery.maybeOf(context)?.disableAnimations ?? false
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                        child: _rating == 0
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(top: AppSpacing.md),
                                child: Text(
                                  _ratingLabel(),
                                  style: textTheme.titleMedium?.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      AppStaggeredEntrance(
                        index: 3,
                        child: AppTextField(
                          controller: _commentController,
                          label: 'Conte-nos mais (opcional)',
                          minLines: 3,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
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
                  label: 'Enviar avaliação',
                  isLoading: _submitting,
                  onPressed: _rating == 0 || _submitting ? null : _submit,
                ),
              ),
            ],
          ),
          Positioned.fill(
            child: AppSuccessFeedback(
              visible: _showSuccessFeedback,
              message: 'Avaliação enviada',
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingStars extends StatelessWidget {
  const _RatingStars({required this.rating, required this.onChanged});

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Avaliação de $rating em 5 estrelas',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 1; index <= 5; index++)
            _RatingStar(
              index: index,
              selected: index <= rating,
              onPressed: () => onChanged(index),
            ),
        ],
      ),
    );
  }
}

class _RatingStar extends StatelessWidget {
  const _RatingStar({
    required this.index,
    required this.selected,
    required this.onPressed,
  });

  final int index;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return IconButton(
      onPressed: onPressed,
      tooltip: '$index estrelas',
      iconSize: 36,
      icon: AnimatedScale(
        scale: selected ? 1 : 0.94,
        duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: Icon(
          selected ? Icons.star_rounded : Icons.star_border_rounded,
          color: AppColors.logoAccent,
        ),
      ),
    );
  }
}
