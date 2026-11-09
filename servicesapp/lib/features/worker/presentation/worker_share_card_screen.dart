import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_links.dart';
import '../../../core/router/app_back_navigation.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/utils/price_labels.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/app_toast.dart';
import '../../auth/application/auth_providers.dart';
import '../../ratings/application/rating_providers.dart';
import '../application/worker_plan_features.dart';
import '../application/worker_providers.dart';
import '../data/worker_plan_model.dart';
import 'widgets/worker_share_card_view.dart';
import 'worker_card_export.dart';
import 'worker_card_share.dart';
import 'worker_plan_sheet.dart';

/// `/worker/card`: o cartão partilhável do próprio jardineiro, com QR,
/// imagem, PDF (Pro e Pro+) e link.
class WorkerShareCardScreen extends ConsumerStatefulWidget {
  const WorkerShareCardScreen({super.key});

  @override
  ConsumerState<WorkerShareCardScreen> createState() =>
      _WorkerShareCardScreenState();
}

class _WorkerShareCardScreenState extends ConsumerState<WorkerShareCardScreen> {
  final _cardKey = GlobalKey();
  bool _busy = false;

  Future<void> _export(Future<void> Function() action) async {
    final toast = AppToast.of(context);
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      toast.error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserProvider)?.id;
    final profileAsync = ref.watch(workerProfileProvider);
    final serviceTypes = ref.watch(serviceTypesProvider).asData?.value ?? [];
    final plan =
        ref.watch(myWorkerPlanProvider).asData?.value ?? WorkerPlan.unavailable;
    final profile = profileAsync.asData?.value;

    if (profile == null || userId == null) {
      return Scaffold(
        body: profileAsync.hasError
            ? Center(child: Text(friendlyError(profileAsync.error!)))
            : const AppScreenLoadingSkeleton(),
      );
    }

    final summary = ref.watch(ratingSummaryProvider(userId)).asData?.value;
    final serviceName = serviceTypes
        .where((t) => profile.serviceTypeIds.contains(t.id))
        .map((t) => t.name)
        .firstOrNull;
    final parts = [
      ?serviceName,
      if (profile.locationName.isNotEmpty) profile.locationName,
    ];
    final ratingLabel = summary == null || summary.ratingCount == 0
        ? null
        : '${decimalLabel(summary.avgRating, 1)} · '
            '${summary.ratingCount == 1 ? '1 avaliação' : '${summary.ratingCount} avaliações'}';
    final linkUrl = AppLinks.publicWorkerProfileUrl(userId, source: 'link');
    final displayUrl = AppLinks.publicWorkerProfileUrl(userId)
        .replaceFirst(RegExp(r'^https?://'), '');

    return WorkerShareCardView(
      data: WorkerShareCardViewData(
        name: profile.fullName,
        professionLocationLabel:
            parts.isEmpty ? 'Jardineiro ProJardim' : parts.join(' · '),
        ratingLabel: ratingLabel,
        avatarUrl: profile.avatarUrl,
        qrUrl: workerPublicCardQrUrl(userId),
        displayUrl: displayUrl,
        planTier: plan.tier,
        canExportPdf: plan.tier.canExportCardPdf,
      ),
      cardKey: _cardKey,
      busy: _busy,
      onBack: () => goBackOrToRoleHome(context),
      onShareImage: () => _export(() async {
        final png = await captureCardPng(_cardKey);
        await shareCardImage(
          png,
          text: 'Vê o meu perfil na ProJardim: $linkUrl',
        );
      }),
      onSavePdf: () {
        if (!plan.tier.canExportCardPdf) {
          showWorkerPlanSheet(context, plan);
          return;
        }
        _export(() async {
          final png = await captureCardPng(_cardKey);
          final pdf = await buildCardPdf(png);
          await shareCardPdf(pdf);
        });
      },
      onSendLink: () => shareWorkerPublicCard(userId),
      onCopyLink: () async {
        final toast = AppToast.of(context);
        await Clipboard.setData(ClipboardData(text: linkUrl));
        toast.show('Link copiado.');
      },
    );
  }
}

