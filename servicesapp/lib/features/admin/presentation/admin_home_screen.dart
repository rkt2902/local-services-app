import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_motion.dart';
import '../application/admin_providers.dart';
import 'widgets/admin_overview_tab.dart';
import 'widgets/admin_workers_tab.dart';

enum _AdminTab { overview, workers }

/// Painel de administração (fase 1): visão geral e jardineiros. Só se
/// chega aqui pelo [AdminGateScreen], depois do segundo fator.
class AdminHomeScreen extends ConsumerStatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  ConsumerState<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends ConsumerState<AdminHomeScreen> {
  _AdminTab _tab = _AdminTab.overview;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        titleSpacing: AppSpacing.lg,
        title: Text(
          'Administração',
          style: textTheme.displaySmall?.copyWith(color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            tooltip: 'Terminar sessão',
            onPressed: () => ref.read(adminRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout_rounded,
                color: AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  AppFilterChip(
                    label: 'Visão geral',
                    leadingIcon: Icons.insights_rounded,
                    selected: _tab == _AdminTab.overview,
                    onPressed: () =>
                        setState(() => _tab = _AdminTab.overview),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppFilterChip(
                    label: 'Jardineiros',
                    leadingIcon: Icons.groups_outlined,
                    selected: _tab == _AdminTab.workers,
                    onPressed: () => setState(() => _tab = _AdminTab.workers),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AppFadeThroughSwitcher(
                switchKey: _tab,
                child: switch (_tab) {
                  _AdminTab.overview => const AdminOverviewTab(),
                  _AdminTab.workers => const AdminWorkersTab(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
