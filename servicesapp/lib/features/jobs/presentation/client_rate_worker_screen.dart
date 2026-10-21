import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../../core/widgets/rating_stars_input.dart';
import '../../ratings/application/rating_providers.dart';
import '../../worker/application/worker_providers.dart';
import '../../../core/widgets/app_toast.dart';

/// Cliente avalia o trabalho (jardineiro principal e ajudantes) pela RPC
/// `submit_client_rating`, a mesma do cartão "Avaliar agora" do detalhe do
/// pedido. Antes chamava `submit_principal_rating`, que só aceita o
/// jardineiro principal como autor e falhava sempre para o cliente.
///
/// Sem botão a abrir este ecrã: a entrada é o cartão "Avaliar agora" em
/// `client_job_detail_screen.dart`. A rota fica para links antigos; se o
/// trabalho já foi avaliado, mostra isso em vez do formulário.
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
    final toast = AppToast.of(context);
    try {
      await ref.read(ratingRepositoryProvider).submitClientRating(
            jobId: widget.jobId,
            stars: _rating,
            comment: _commentController.text.trim().isEmpty
                ? null
                : _commentController.text.trim(),
          );

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
          // T4: sair primeiro, invalidar depois. Sem stack (link direto),
          // vai para o detalhe do pedido em vez de um pop() sem destino.
          final container = ProviderScope.containerOf(context, listen: false);
          goBackOr(context, '/client/job/${widget.jobId}');
          container.invalidate(myRatingForJobProvider(widget.jobId));
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      toast.error(friendlyError(e));
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
    final existingRating =
        ref.watch(myRatingForJobProvider(widget.jobId)).asData?.value;
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
        leading: AppBackButton(fallbackLocation: '/client/job/${widget.jobId}'),
        titleSpacing: 0,
        title: Text(
          'Avaliar',
          style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
        ),
      ),
      body: existingRating != null && !_showSuccessFeedback
          ? _AlreadyRated(
              onViewJob: () => goBackOr(context, '/client/job/${widget.jobId}'),
            )
          : Stack(
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
                          'Avaliar ${workerName.isEmpty ? 'o jardineiro' : workerName}',
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Como foi a tua experiência?',
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // Sem AppStaggeredEntrance a envolver: RatingStarsInput
                      // já tem a sua própria entrada em cascata por estrela
                      // (docs/motion_spec.md §3) — embrulhar duplicaria a
                      // animação de entrada.
                      RatingStarsInput(
                        rating: _rating,
                        onChanged: (rating) => setState(() => _rating = rating),
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
                        index: 2,
                        child: AppTextField(
                          controller: _commentController,
                          label: 'Conta-nos mais (opcional)',
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

class _AlreadyRated extends StatelessWidget {
  const _AlreadyRated({required this.onViewJob});

  final VoidCallback onViewJob;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppStaggeredEntrance(
          index: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.primary),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Já avaliaste este trabalho.',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryActionButton(label: 'Ver pedido', onPressed: onViewJob),
            ],
          ),
        ),
      ),
    );
  }
}
