import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_brand_badge.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../application/admin_providers.dart';
import 'widgets/admin_global_search.dart';
import 'widgets/admin_panel_widgets.dart';

/// Entradas da barra lateral (fase A). Caixa de suporte, Denúncias,
/// Avaliações, Mapa e Registo chegam nas fases B e C.
enum AdminSection {
  overview('Visão geral', Icons.insights_rounded, '/admin'),
  jobs('Pedidos', Icons.assignment_outlined, '/admin/pedidos'),
  clients('Clientes', Icons.person_outline_rounded, '/admin/clientes'),
  workers('Jardineiros', Icons.groups_outlined, '/admin/workers');

  const AdminSection(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;

  /// Secção ativa para um endereço do painel.
  static AdminSection fromLocation(String location) {
    for (final section in [jobs, clients, workers]) {
      if (location == section.route ||
          location.startsWith('${section.route}/')) {
        return section;
      }
    }
    return overview;
  }
}

/// Estrutura do painel depois do segundo fator: barra lateral com as
/// secções e pesquisa global sempre no topo. Num ecrã estreito a barra
/// lateral passa a uma fila de filtros por baixo da pesquisa.
class AdminShell extends ConsumerWidget {
  const AdminShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = AdminSection.fromLocation(location);
    final textTheme = Theme.of(context).textTheme;
    void signOut() => ref.read(adminRepositoryProvider).signOut();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            final top = Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!wide) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'Admin',
                        style: textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  const Expanded(child: AdminGlobalSearch()),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    tooltip: 'Terminar sessão',
                    onPressed: signOut,
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  top,
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        for (final section in AdminSection.values) ...[
                          AppFilterChip(
                            label: section.label,
                            leadingIcon: section.icon,
                            selected: section == current,
                            onPressed: () => context.go(section.route),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                      ],
                    ),
                  ),
                  Expanded(child: child),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: adminSidebarWidth,
                  child: _Sidebar(current: current),
                ),
                const VerticalDivider(width: 1, color: AppColors.divider),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      top,
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current});

  final AdminSection current;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      color: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const Align(alignment: Alignment.centerLeft, child: AppBrandBadge()),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Administração',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final section in AdminSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Material(
                color: section == current
                    ? AppColors.primaryContainer
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.input),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  onTap: () => context.go(section.route),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.s10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          section.icon,
                          size: 20,
                          color: section == current
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            section.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium?.copyWith(
                              color: section == current
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
