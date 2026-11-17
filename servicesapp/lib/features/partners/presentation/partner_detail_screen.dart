import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/address_map_link.dart';
import '../../../core/widgets/app_content_width.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_tab_header.dart';
import '../../../core/widgets/app_toast.dart';
import '../../worker/application/worker_providers.dart';
import '../../worker/data/worker_plan_model.dart';
import '../../worker/presentation/worker_plan_sheet.dart';
import '../application/partner_providers.dart';
import '../data/partner_model.dart';
import 'widgets/partner_detail_view.dart';

/// Ecrã de um parceiro (`/worker/partners/:id`, fora do shell). O corpo é
/// o [PartnerDetailView], que só mostra o que o parceiro tem preenchido.
class PartnerDetailScreen extends ConsumerStatefulWidget {
  const PartnerDetailScreen({required this.partnerId, super.key});

  final String partnerId;

  @override
  ConsumerState<PartnerDetailScreen> createState() =>
      _PartnerDetailScreenState();
}

class _PartnerDetailScreenState extends ConsumerState<PartnerDetailScreen> {
  String get partnerId => widget.partnerId;

  @override
  void initState() {
    super.initState();
    // Conta para o painel (quantos jardineiros abriram este parceiro).
    _log(PartnerEvent.open);
  }

  void _log(PartnerEvent event) =>
      ref.read(partnerRepositoryProvider).logEvent(partnerId, event);

  @override
  Widget build(BuildContext context) {
    final partnersAsync = ref.watch(partnersProvider);
    final partner = partnersAsync.asData?.value
        .where((p) => p.id == partnerId)
        .firstOrNull;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBackHeader(
              title: partner?.name ?? 'Parceiro',
              onBack: () => goBackOrToRoleHome(context),
            ),
            Expanded(
              child: partnersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(AppSpacing.s18),
                  child: AppInlineError(
                    message: friendlyError(e),
                    onRetry: () => ref.invalidate(partnersProvider),
                  ),
                ),
                data: (_) => partner == null
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.s18),
                        child: AppEmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'Parceiro indisponível',
                          message:
                              'Este parceiro já não está na lista. Volta à '
                              'tab Parceiros para ver os que há.',
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.s18,
                          AppSpacing.xs,
                          AppSpacing.s18,
                          AppSpacing.xl,
                        ),
                        child: AppContentWidth(
                          child: PartnerDetailView(
                            partner: partner,
                            onCopyCode: (code) => _copy(context, code),
                            onOpenLink: _openLink,
                            onOpenMap: (lat, lng) {
                              _log(PartnerEvent.openMap);
                              AddressMapLink.openInMaps(lat, lng);
                            },
                            onUnlock: () => showWorkerPlanSheet(
                              context,
                              ref.read(myWorkerPlanProvider).asData?.value ??
                                  WorkerPlan.unavailable,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, String code) async {
    final toast = AppToast.of(context);
    _log(PartnerEvent.copyCode);
    await Clipboard.setData(ClipboardData(text: code));
    toast.show('Código copiado.');
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    _log(PartnerEvent.openLink);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
