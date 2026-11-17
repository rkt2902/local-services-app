import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_tab_header.dart';
import '../application/partner_providers.dart';
import '../data/partner_model.dart';
import 'widgets/partner_banner_card.dart';

/// Tab "Parceiros" do jardineiro (`/worker/partners`, 0082). Só tem botão
/// no menu quando há parceiros; a lista vem do painel de admin.
class PartnersScreen extends ConsumerWidget {
  const PartnersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.watch(partnersProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppTabHeader(overline: 'Benefícios', title: 'Parceiros'),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => ref.refresh(partnersProvider.future),
                child: AppFadeThroughSwitcher(
                  switchKey: partnersAsync.isLoading && !partnersAsync.hasValue
                      ? 'loading'
                      : partnersAsync.hasError && !partnersAsync.hasValue
                      ? 'error'
                      : 'data',
                  child: partnersAsync.when(
                    skipLoadingOnRefresh: true,
                    loading: () => const _PartnersSkeleton(),
                    error: (e, _) => ListView(
                      padding: const EdgeInsets.all(AppSpacing.s18),
                      children: [
                        AppInlineError(
                          message: friendlyError(e),
                          onRetry: () => ref.invalidate(partnersProvider),
                        ),
                      ],
                    ),
                    data: (partners) => PartnersList(
                      partners: partners,
                      onOpen: (p) => context.push('/worker/partners/${p.id}'),
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
}

/// A lista em si (sem providers, para os testes).
class PartnersList extends StatelessWidget {
  const PartnersList({required this.partners, required this.onOpen, super.key});

  final List<Partner> partners;
  final ValueChanged<Partner> onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (partners.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.s18),
        children: const [
          AppEmptyState(
            icon: Icons.storefront_outlined,
            title: 'Ainda sem parceiros',
            message: 'Quando houver descontos de parceiros, aparecem aqui.',
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s18,
        AppSpacing.md,
        AppSpacing.s18,
        AppSpacing.xl,
      ),
      itemCount: partners.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Text(
            'Descontos e vantagens de quem trabalha com o ProJardim. '
            'Toca num parceiro para ver os detalhes.',
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          );
        }
        final p = partners[i - 1];
        return AppStaggeredEntrance(
          index: i < 6 ? i : 6,
          child: PartnerBannerCard(partner: p, onTap: () => onOpen(p)),
        );
      },
    );
  }
}

class _PartnersSkeleton extends StatelessWidget {
  const _PartnersSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.s18),
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          AppSkeletonShimmer(
            child: Container(
              height: AppSizes.partnerBannerHeight + AppSizes.buttonHeight,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
