import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/enums.dart';
import '../../../core/models/worker_public_card_feature_access.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/direct_request_auth_context.dart';
import '../../auth/application/session_provider.dart';
import '../../client/application/client_create_job_wizard_provider.dart';
import '../../client/presentation/card_request_launcher.dart';
import '../../jobs/application/direct_request_labels.dart';
import '../../onboarding/application/onboarding_providers.dart';
import '../../ratings/presentation/worker_ratings_sheet.dart';
import '../application/worker_providers.dart';
import '../data/worker_public_card_model.dart';
import 'widgets/worker_public_card_view.dart';
import 'worker_card_share.dart';

/// Cartão público do jardineiro `/w/:id`, aberto por link, QR ou dentro da
/// app, com ou sem sessão. Ver `worker_public_card` (0033, 0051, 0059) para
/// o que fica deliberadamente de fora (telefone, morada exata, raio).
///
/// A7: o rodapé depende de quem vê (cliente, visitante sem conta, outro
/// jardineiro, o próprio) e cada abertura conta uma visita no servidor
/// (`log_worker_card_visit`), com a origem de [source].
class WorkerPublicProfileScreen extends ConsumerStatefulWidget {
  const WorkerPublicProfileScreen({
    required this.workerId,
    this.source,
    super.key,
  });

  final String workerId;

  /// `?src=` do endereço: `qr`, `link` ou `app`. Sem nada conta como link
  /// (alguém colou o endereço à mão).
  final String? source;

  @override
  ConsumerState<WorkerPublicProfileScreen> createState() =>
      _WorkerPublicProfileScreenState();
}

class _WorkerPublicProfileScreenState
    extends ConsumerState<WorkerPublicProfileScreen> {
  static const _sources = {'qr', 'link', 'app'};

  /// Visita registada no servidor; vai com o pedido para ligar a conta nova
  /// (ou o pedido) ao QR/link de onde veio.
  Future<String?>? _visit;

  @override
  void initState() {
    super.initState();
    _visit = _logVisit();
  }

  Future<String?> _logVisit() async {
    final source =
        _sources.contains(widget.source) ? widget.source! : 'link';
    String? deviceKey;
    try {
      deviceKey = await ref.read(directRequestAuthStoreProvider).deviceKey();
    } catch (_) {
      deviceKey = null;
    }
    return ref.read(workerRepositoryProvider).logCardVisit(
          workerId: widget.workerId,
          source: source,
          deviceKey: deviceKey,
        );
  }

  WorkerPublicCardViewerMode _viewerMode() {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return WorkerPublicCardViewerMode.signedOut;
    if (userId == widget.workerId) {
      return WorkerPublicCardViewerMode.ownerPreview;
    }
    final role = ref.watch(sessionStatusProvider).asData?.value.role;
    return role == UserRole.worker
        ? WorkerPublicCardViewerMode.anotherWorker
        : WorkerPublicCardViewerMode.clientSignedIn;
  }

  /// Hoje todos os jardineiros têm tudo ligado; o servidor já devolve as
  /// capacidades para quando o plano Pro as separar. A partilha segue o
  /// próprio cartão.
  static WorkerPublicCardFeatureAccess _accessFor(WorkerPublicCard card) =>
      WorkerPublicCardFeatureAccess(
        canUsePublicCard: card.canUsePublicCard,
        canSharePublicCard: card.canUsePublicCard,
        canReceiveDirectRequests: card.canReceiveDirectRequests,
      );

  static String? _latestReviewLabel(WorkerPublicCard card) {
    final comment = card.latestReviewComment?.trim() ?? '';
    if (comment.isEmpty) return null;
    final author = card.latestReviewAuthor?.trim() ?? '';
    return author.isEmpty ? '"$comment"' : '"$comment" · $author';
  }

  Future<String?> _visitId() async {
    try {
      return await _visit;
    } catch (_) {
      return null;
    }
  }

  Future<void> _rememberForAuth(WorkerPublicCard card) async {
    // Quem chega pelo cartão já sabe ao que vem: o router não o desvia para
    // o onboarding a caminho do registo.
    try {
      await ref.read(hasSeenOnboardingProvider.notifier).markSeen();
    } catch (_) {}
    await ref.read(directRequestAuthProvider.notifier).save(
          DirectRequestAuthContext(
            workerId: card.workerId,
            workerName: card.fullName,
            workerAvatarUrl: card.avatarUrl ?? '',
            visitId: await _visitId(),
            savedAt: DateTime.now(),
          ),
        );
  }

  Future<void> _startDirectRequest(
    WorkerPublicCard card,
    WorkerPublicCardViewerMode mode,
  ) async {
    if (mode == WorkerPublicCardViewerMode.signedOut) {
      // Registo normal; no fim volta ao pedido para este jardineiro
      // (ver resumePendingCardRequest no início do cliente).
      await _rememberForAuth(card);
      if (mounted) context.go('/signup');
      return;
    }
    final visitId = await _visitId();
    if (!mounted) return;
    startCardDirectRequest(
      context,
      ref,
      workerId: card.workerId,
      workerName: card.fullName,
      workerAvatarUrl: card.avatarUrl ?? '',
      visitId: visitId,
    );
  }

  Future<void> _login(WorkerPublicCard? card) async {
    if (card != null) await _rememberForAuth(card);
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final cardAsync = ref.watch(workerPublicCardProvider(widget.workerId));
    final mode = _viewerMode();
    final isVisitor = mode == WorkerPublicCardViewerMode.signedOut;
    final card = cardAsync.asData?.value;

    final dataAsync = cardAsync.whenData(
      (card) => card == null
          ? null
          : WorkerPublicCardViewData(
              card: card,
              featureAccess: _accessFor(card),
              viewerMode: mode,
              directRequestActionLabel:
                  cardDirectRequestActionLabel(card.fullName),
              latestReviewLabel: _latestReviewLabel(card),
            ),
    );

    return WorkerPublicCardView(
      dataAsync: dataAsync,
      onBack: () =>
          isVisitor ? goBackOr(context, '/') : goBackOrToRoleHome(context),
      onStartDirectRequest: (_) {
        if (card != null) _startDirectRequest(card, mode);
      },
      onShareCard: shareWorkerPublicCard,
      onLogin: () => _login(card),
      onRetry: () =>
          ref.invalidate(workerPublicCardProvider(widget.workerId)),
      // As avaliações individuais só se leem com sessão (RLS de ratings);
      // o visitante vê só a média.
      onRatingsPressed: isVisitor || card == null
          ? null
          : () => showWorkerRatingsSheet(
                context,
                workerId: card.workerId,
                workerName: card.fullName,
              ),
      onCreateGenericRequest: switch (mode) {
        WorkerPublicCardViewerMode.clientSignedIn => () {
            ref.read(clientCreateJobWizardProvider.notifier).clearDirectWorker();
            context.push('/client/create-job');
          },
        WorkerPublicCardViewerMode.signedOut => () => context.go('/signup'),
        _ => null,
      },
    );
  }
}
