import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_presentation.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/app_status_badge.dart';
import '../../../../core/widgets/primary_action_button.dart';

/// Dados visuais de um pedido disponível.
///
/// A integração (worker_available_jobs_screen.dart) mapeia os models reais
/// para este objeto — este ficheiro não consulta Supabase nem sabe o que é
/// um `JobRequest`.
class WorkerAvailableJobViewData {
  const WorkerAvailableJobViewData({
    required this.id,
    required this.title,
    required this.locationLabel,
    required this.scheduleLabel,
    required this.priceLabel,
    required this.icon,
    this.badge,
  });

  final String id;
  final String title;
  final String locationLabel;
  final String scheduleLabel;
  final String priceLabel;
  final IconData icon;

  /// Exemplos:
  ///
  /// Novo:
  /// AppStatusPresentation(label: 'Novo', color: AppStatusColor.success)
  ///
  /// Urgente:
  /// urgentStatusPresentation
  final AppStatusPresentation? badge;
}

class WorkerAvailableJobsFilters {
  const WorkerAvailableJobsFilters({
    required this.selectedServiceTypeIds,
    required this.urgentOnly,
  });

  final Set<String> selectedServiceTypeIds;
  final bool urgentOnly;

  WorkerAvailableJobsFilters copyWith({
    Set<String>? selectedServiceTypeIds,
    bool? urgentOnly,
  }) {
    return WorkerAvailableJobsFilters(
      selectedServiceTypeIds:
          selectedServiceTypeIds ?? this.selectedServiceTypeIds,
      urgentOnly: urgentOnly ?? this.urgentOnly,
    );
  }
}

/// Ecrã de pedidos disponíveis — genérico sobre [TServiceType].
///
/// [TServiceType] representa o model real devolvido pelo
/// `serviceTypesProvider` da feature `worker`. Este widget vive em
/// `features/worker/presentation/widgets/` (não em `core/widgets/`) porque,
/// apesar de genérico no tipo, é conceptualmente específico à feature
/// `worker` (categoria/urgente são filtros de pedidos, não um conceito
/// partilhado por 2+ features — ver architecture.md).
///
/// Esta abordagem permite ligar o provider real sem inventar:
/// - o caminho do import;
/// - o nome do model;
/// - os nomes dos campos.
class WorkerAvailableJobsScreen<TServiceType> extends StatefulWidget {
  const WorkerAvailableJobsScreen({
    required this.jobs,
    required this.serviceTypesAsync,
    required this.serviceTypeIdOf,
    required this.serviceTypeLabelOf,
    required this.serviceTypeIconOf,
    required this.onJobPressed,
    required this.onSearchChanged,
    required this.onFiltersPressed,
    required this.onFiltersChanged,
    required this.onDistancePressed,
    super.key,
    this.initialSearchQuery = '',
    this.initialFilters = const WorkerAvailableJobsFilters(
      selectedServiceTypeIds: {},
      urgentOnly: false,
    ),
    this.distanceLabel = '≤ 5 km',
    this.isLoadingJobs = false,
    this.jobsErrorMessage,
    this.onRetryJobs,
    this.appBarActions,
  });

  final List<WorkerAvailableJobViewData> jobs;

  /// Passar aqui o valor já resolvido de serviceTypesProvider — este widget
  /// não depende do Riverpod, só recebe o AsyncValue já observado pelo
  /// chamador (padrão "dumb widget" já usado no resto da app).
  final AsyncValue<List<TServiceType>> serviceTypesAsync;

  /// Adaptadores do model real.
  final String Function(TServiceType serviceType) serviceTypeIdOf;
  final String Function(TServiceType serviceType) serviceTypeLabelOf;
  final IconData Function(TServiceType serviceType) serviceTypeIconOf;

  final ValueChanged<String> onJobPressed;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onFiltersPressed;
  final ValueChanged<WorkerAvailableJobsFilters> onFiltersChanged;
  final VoidCallback onDistancePressed;

  final String initialSearchQuery;
  final WorkerAvailableJobsFilters initialFilters;
  final String distanceLabel;

  final bool isLoadingJobs;
  final String? jobsErrorMessage;
  final VoidCallback? onRetryJobs;

  /// Ações extra (ex.: notificações, atalho para pedidos de ajuda) — o
  /// mockup original não tinha AppBar; adicionado para não perder esses
  /// dois pontos de navegação já existentes no ecrã antigo. Quando null,
  /// não há AppBar (comportamento igual ao mockup de referência).
  final List<Widget>? appBarActions;

  @override
  State<WorkerAvailableJobsScreen<TServiceType>> createState() {
    return _WorkerAvailableJobsScreenState<TServiceType>();
  }
}

class _WorkerAvailableJobsScreenState<TServiceType>
    extends State<WorkerAvailableJobsScreen<TServiceType>> {
  late final TextEditingController _searchController;
  late WorkerAvailableJobsFilters _filters;

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController(
      text: widget.initialSearchQuery,
    );

    _filters = WorkerAvailableJobsFilters(
      selectedServiceTypeIds: {
        ...widget.initialFilters.selectedServiceTypeIds,
      },
      urgentOnly: widget.initialFilters.urgentOnly,
    );
  }

  @override
  void didUpdateWidget(
    covariant WorkerAvailableJobsScreen<TServiceType> oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialFilters != widget.initialFilters) {
      _filters = WorkerAvailableJobsFilters(
        selectedServiceTypeIds: {
          ...widget.initialFilters.selectedServiceTypeIds,
        },
        urgentOnly: widget.initialFilters.urgentOnly,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
    widget.onSearchChanged('');
  }

  void _toggleUrgent() {
    setState(() {
      _filters = _filters.copyWith(
        urgentOnly: !_filters.urgentOnly,
      );
    });

    widget.onFiltersChanged(_filters);
  }

  Future<void> _openCategoryFilter(
    AsyncValue<List<TServiceType>> serviceTypesAsync,
  ) async {
    final selectedIds = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.textPrimary.withValues(
        alpha: 0.32,
      ),
      builder: (context) {
        return _CategoryFilterSheet<TServiceType>(
          serviceTypesAsync: serviceTypesAsync,
          initialSelectedIds: _filters.selectedServiceTypeIds,
          serviceTypeIdOf: widget.serviceTypeIdOf,
          serviceTypeLabelOf: widget.serviceTypeLabelOf,
          serviceTypeIconOf: widget.serviceTypeIconOf,
        );
      },
    );

    if (!mounted || selectedIds == null) {
      return;
    }

    setState(() {
      _filters = _filters.copyWith(
        selectedServiceTypeIds: selectedIds,
      );
    });

    widget.onFiltersChanged(_filters);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final serviceTypesAsync = widget.serviceTypesAsync;

    final categoryCount = _filters.selectedServiceTypeIds.length;

    final categoryLabel = categoryCount == 0
        ? 'Categoria'
        : 'Categoria ($categoryCount)';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.appBarActions == null
          ? null
          : AppBar(
              backgroundColor: AppColors.background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              actions: widget.appBarActions,
            ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'Pedidos disponíveis',
                style: textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
              ),
              child: AppSearchField(
                controller: _searchController,
                hintText: 'Procurar por serviço...',
                onChanged: (value) {
                  setState(() {});
                  widget.onSearchChanged(value.trim());
                },
                onSubmitted: (value) {
                  widget.onSearchChanged(value.trim());
                },
                onClear: _clearSearch,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                children: [
                  FilledButton.icon(
                    onPressed: widget.onFiltersPressed,
                    style: ButtonStyle(
                      elevation: const WidgetStatePropertyAll(0),
                      backgroundColor:
                          WidgetStateProperty.resolveWith<Color>(
                        (states) {
                          if (states.contains(WidgetState.pressed)) {
                            return AppColors.primaryPressed;
                          }

                          return AppColors.primary;
                        },
                      ),
                      foregroundColor:
                          const WidgetStatePropertyAll(
                        AppColors.surface,
                      ),
                      padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                      ),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadius.pill,
                          ),
                        ),
                      ),
                      textStyle: WidgetStatePropertyAll(
                        textTheme.labelMedium,
                      ),
                    ),
                    icon: const Icon(
                      Icons.tune_rounded,
                      size: 18,
                    ),
                    label: const Text('Filtros'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppFilterChip(
                    label: categoryLabel,
                    trailingIcon: Icons.keyboard_arrow_down_rounded,
                    selected: categoryCount > 0,
                    onPressed: () {
                      _openCategoryFilter(serviceTypesAsync);
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppFilterChip(
                    label: widget.distanceLabel,
                    onPressed: widget.onDistancePressed,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  AppFilterChip(
                    label: 'Urgente',
                    selected: _filters.urgentOnly,
                    onPressed: _toggleUrgent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(
              height: 1,
              color: AppColors.divider,
            ),
            Expanded(
              child: _JobsContent(
                jobs: widget.jobs,
                loading: widget.isLoadingJobs,
                errorMessage: widget.jobsErrorMessage,
                onRetry: widget.onRetryJobs,
                onJobPressed: widget.onJobPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobsContent extends StatelessWidget {
  const _JobsContent({
    required this.jobs,
    required this.loading,
    required this.errorMessage,
    required this.onRetry,
    required this.onJobPressed,
  });

  final List<WorkerAvailableJobViewData> jobs;
  final bool loading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final ValueChanged<String> onJobPressed;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      );
    }

    if (errorMessage != null) {
      return _JobsMessageState(
        icon: Icons.error_outline_rounded,
        message: errorMessage!,
        actionLabel: onRetry == null ? null : 'Tentar novamente',
        onActionPressed: onRetry,
      );
    }

    if (jobs.isEmpty) {
      return const _JobsMessageState(
        icon: Icons.search_off_rounded,
        message: 'Não existem pedidos disponíveis para estes filtros.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: jobs.length,
      separatorBuilder: (_, _) {
        return const SizedBox(height: AppSpacing.sm);
      },
      itemBuilder: (context, index) {
        final job = jobs[index];

        return _AvailableJobCard(
          job: job,
          onPressed: () => onJobPressed(job.id),
        );
      },
    );
  }
}

class _AvailableJobCard extends StatelessWidget {
  const _AvailableJobCard({
    required this.job,
    required this.onPressed,
  });

  final WorkerAvailableJobViewData job;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: AppColors.divider,
            ),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ServiceIcon(icon: job.icon),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          job.locationLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (job.badge != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    AppStatusBadge.fromPresentation(
                      presentation: job.badge!,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job.scheduleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    job.priceLabel,
                    maxLines: 1,
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceIcon extends StatelessWidget {
  const _ServiceIcon({
    required this.icon,
  });

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Icon(
        icon,
        size: 22,
        color: AppColors.primary,
      ),
    );
  }
}

class _JobsMessageState extends StatelessWidget {
  const _JobsMessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onActionPressed,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (actionLabel != null && onActionPressed != null) ...[
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: onActionPressed,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryFilterSheet<TServiceType> extends StatefulWidget {
  const _CategoryFilterSheet({
    required this.serviceTypesAsync,
    required this.initialSelectedIds,
    required this.serviceTypeIdOf,
    required this.serviceTypeLabelOf,
    required this.serviceTypeIconOf,
  });

  final AsyncValue<List<TServiceType>> serviceTypesAsync;
  final Set<String> initialSelectedIds;
  final String Function(TServiceType serviceType) serviceTypeIdOf;
  final String Function(TServiceType serviceType) serviceTypeLabelOf;
  final IconData Function(TServiceType serviceType) serviceTypeIconOf;

  @override
  State<_CategoryFilterSheet<TServiceType>> createState() {
    return _CategoryFilterSheetState<TServiceType>();
  }
}

class _CategoryFilterSheetState<TServiceType>
    extends State<_CategoryFilterSheet<TServiceType>> {
  late final TextEditingController _searchController;
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController();
    _selectedIds = {
      ...widget.initialSelectedIds,
    };
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Container(
      height: screenHeight * 0.68,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Categoria',
                    style: textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : _clearSelection,
                  child: const Text('Limpar'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
            ),
            child: AppSearchField(
              controller: _searchController,
              hintText: 'Procurar categoria...',
              onChanged: (_) => setState(() {}),
              onClear: _clearSearch,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: widget.serviceTypesAsync.when(
              loading: () {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                  ),
                );
              },
              error: (_, _) {
                return const _JobsMessageState(
                  icon: Icons.error_outline_rounded,
                  message:
                      'Não foi possível carregar as categorias.',
                );
              },
              data: (serviceTypes) {
                final query = _searchController.text
                    .trim()
                    .toLowerCase();

                final filtered = serviceTypes.where((serviceType) {
                  final label = widget
                      .serviceTypeLabelOf(serviceType)
                      .toLowerCase();

                  return query.isEmpty || label.contains(query);
                }).toList();

                if (filtered.isEmpty) {
                  return const _JobsMessageState(
                    icon: Icons.search_off_rounded,
                    message: 'Nenhuma categoria encontrada.',
                  );
                }

                final remainingCount =
                    filtered.length > 9 ? filtered.length - 9 : 0;

                return Column(
                  children: [
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        itemCount: filtered.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: AppSpacing.xs,
                          mainAxisSpacing: AppSpacing.xs,
                          childAspectRatio: 1.05,
                        ),
                        itemBuilder: (context, index) {
                          final serviceType = filtered[index];
                          final id = widget.serviceTypeIdOf(
                            serviceType,
                          );
                          final label = widget.serviceTypeLabelOf(
                            serviceType,
                          );
                          final icon = widget.serviceTypeIconOf(
                            serviceType,
                          );

                          return _CategoryTile(
                            label: label,
                            icon: icon,
                            selected: _selectedIds.contains(id),
                            onPressed: () => _toggle(id),
                          );
                        },
                      ),
                    ),
                    if (remainingCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.xs,
                        ),
                        child: Text(
                          '+$remainingCount categorias · role para ver mais',
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                );
              },
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
              label: 'Aplicar (${_selectedIds.length})',
              onPressed: () {
                Navigator.of(context).pop(
                  Set<String>.unmodifiable(_selectedIds),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? AppColors.primaryContainer
            : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : AppColors.divider,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 24,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
