import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_back_navigation.dart';
import '../../../core/widgets/app_back_button.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_step_progress.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../../core/widgets/service_category_section.dart';
import '../../../core/widgets/service_icon.dart';
import '../../jobs/application/direct_request_labels.dart';
import '../../jobs/application/job_providers.dart';
import '../../worker/application/worker_providers.dart';
import '../../worker/data/service_type_model.dart';
import '../application/client_create_job_wizard_provider.dart';
import 'widgets/direct_request_create_header.dart';
import 'widgets/direct_request_services_state.dart';

/// Passo 1/3 de "Criar pedido" — escolha do tipo de serviço.
///
/// `serviceTypesProvider` é o mesmo provider já usado do lado do worker
/// (re-exportado por `jobs/application/job_providers.dart`).
class ClientCreateJobServiceScreen extends ConsumerStatefulWidget {
  const ClientCreateJobServiceScreen({super.key, this.fromReview = false});

  /// `true` quando alcançado via "Editar" a partir da revisão (passo 4) —
  /// o formulário mostra os dados já preenchidos (como sempre fez) mas
  /// "Continuar" volta direto à revisão em vez de seguir a sequência
  /// normal do wizard.
  final bool fromReview;

  @override
  ConsumerState<ClientCreateJobServiceScreen> createState() {
    return _ClientCreateJobServiceScreenState();
  }
}

class _ClientCreateJobServiceScreenState
    extends ConsumerState<ClientCreateJobServiceScreen> {
  late final TextEditingController _searchController;

  String? _selectedServiceTypeId;

  /// Categoria aberta (nome); `null` com todas fechadas.
  String? _expandedCategory;

  /// `true` depois de o cliente abrir ou fechar uma categoria.
  bool _categoryTouched = false;

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController();
    _selectedServiceTypeId =
        ref.read(clientCreateJobWizardProvider).serviceTypeId;
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _continue() {
    final id = _selectedServiceTypeId;
    if (id == null) return;
    ref.read(clientCreateJobWizardProvider.notifier).setService(id);
    if (widget.fromReview) {
      goBackOr(context, '/client/create-job/review');
    } else {
      context.push('/client/create-job/schedule');
    }
  }

  Widget _serviceGrid(List<ServiceType> types) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.xs,
        mainAxisSpacing: AppSpacing.xs,
        childAspectRatio: 0.8,
      ),
      itemCount: types.length,
      itemBuilder: (context, index) {
        final serviceType = types[index];
        return ClientServiceTypeTile(
          id: serviceType.id,
          label: serviceType.name,
          icon: serviceIconFor(serviceType.icon),
          selected: _selectedServiceTypeId == serviceType.id,
          onSelected: (id) => setState(() => _selectedServiceTypeId = id),
        );
      },
    );
  }

  /// Pedido pelo cartão (A7): só os serviços deste jardineiro, numa grelha
  /// sem categorias. Sem serviços, "Ver todos os serviços" volta à lista
  /// normal e o pedido continua a ir primeiro para ele.
  Widget _cardServices(
    ClientCreateJobWizardState wizard,
    AsyncValue<List<ServiceType>> serviceTypesAsync,
    String query,
  ) {
    final workerId = wizard.directCardWorkerId!;
    final cardAsync = ref.watch(workerPublicCardProvider(workerId));
    if (cardAsync.hasError || serviceTypesAsync.hasError) {
      return DirectRequestServicesError(
        onRetry: () {
          ref.invalidate(workerPublicCardProvider(workerId));
          if (serviceTypesAsync.hasError) ref.invalidate(serviceTypesProvider);
        },
      );
    }
    final card = cardAsync.asData?.value;
    final types = serviceTypesAsync.asData?.value;
    if (types == null || (card == null && cardAsync.isLoading)) {
      return const DirectRequestServicesSkeleton();
    }
    final offered = card?.serviceTypeIds ?? const <String>[];
    final workerTypes = types.where((t) => offered.contains(t.id)).toList();
    if (workerTypes.isEmpty) {
      return DirectRequestServicesEmpty(
        workerName: firstNameOr(wizard.directWorkerName, 'O jardineiro'),
        onShowAllServices: () => ref
            .read(clientCreateJobWizardProvider.notifier)
            .showAllServices(),
      );
    }
    final matches = query.isEmpty
        ? workerTypes
        : workerTypes
            .where((s) => s.name.toLowerCase().contains(query))
            .toList();
    if (matches.isEmpty) {
      return Text(
        'Nenhum serviço encontrado.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
      );
    }
    return _serviceGrid(matches);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final serviceTypesAsync = ref.watch(serviceTypesProvider);
    final query = _searchController.text.trim().toLowerCase();
    final wizard = ref.watch(clientCreateJobWizardProvider);
    final onlyWorkerServices =
        wizard.isCardRequest && !wizard.directShowAllServices;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        leading: const AppBackButton(),
        titleSpacing: 0,
        title: Text(
          'Criar pedido',
          style: textTheme.titleLarge?.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: AppStepProgress(currentStep: 1, totalSteps: 4),
          ),
          const WizardCardRequestHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppStaggeredEntrance(
                    index: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Que serviço precisa?',
                          style: textTheme.titleMedium?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Pesquise ou escolha uma categoria.',
                          style: textTheme.labelMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 1,
                    child: AppSearchField(
                      controller: _searchController,
                      hintText: 'Procurar serviço...',
                      onChanged: (_) => setState(() {}),
                      onClear: _clearSearch,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 2,
                    child: onlyWorkerServices
                        ? _cardServices(wizard, serviceTypesAsync, query)
                        : serviceTypesAsync.when(
                    loading: () => GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: AppSpacing.xs,
                        mainAxisSpacing: AppSpacing.xs,
                        // 0.8 em vez de 0.95 — nomes de categoria com 2
                        // linhas (ex.: "Montagem de jardim") faziam overflow
                        // por ~2px na razão anterior.
                        childAspectRatio: 0.8,
                      ),
                      itemCount: 6,
                      itemBuilder: (context, index) => AppSkeletonShimmer(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.input),
                          ),
                        ),
                      ),
                    ),
                    error: (e, _) => Text(
                      friendlyError(e),
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    data: (serviceTypes) {
                      final groups = groupServiceTypes(serviceTypes);

                      // Com pesquisa: procura em todas as categorias e
                      // esconde os separadores.
                      if (query.isNotEmpty) {
                        final matches = serviceTypes
                            .where((s) => s.name.toLowerCase().contains(query))
                            .toList();
                        if (matches.isEmpty) {
                          return Text(
                            'Nenhum serviço encontrado.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          );
                        }
                        return _serviceGrid(matches);
                      }

                      if (groups.isEmpty) {
                        return Text(
                          'Nenhum serviço disponível.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        );
                      }

                      // Uma categoria aberta de cada vez. Antes de o
                      // cliente tocar em alguma, abre a do serviço já
                      // escolhido (ao voltar da revisão) ou fica tudo
                      // fechado.
                      final selectedType = serviceTypes
                          .where((t) => t.id == _selectedServiceTypeId)
                          .firstOrNull;
                      final expandedName = _categoryTouched
                          ? _expandedCategory
                          : selectedType?.categoryName;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final group in groups) ...[
                            ServiceCategorySection(
                              icon: serviceIconFor(group.icon),
                              title: group.name,
                              summary: group.types
                                      .any((t) => t.id == selectedType?.id)
                                  ? selectedType!.name
                                  : '${group.types.length} serviços',
                              highlighted: group.types
                                  .any((t) => t.id == selectedType?.id),
                              expanded: expandedName == group.name,
                              onToggle: () => setState(() {
                                _categoryTouched = true;
                                _expandedCategory = expandedName == group.name
                                    ? null
                                    : group.name;
                              }),
                              child: _serviceGrid(group.types),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                          ],
                        ],
                      );
                    },
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
              label: 'Continuar',
              onPressed: _selectedServiceTypeId == null ? null : _continue,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile reutilizável de categoria de serviço.
class ClientServiceTypeTile extends StatelessWidget {
  const ClientServiceTypeTile({
    required this.id,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected ? AppColors.primaryContainer : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: () => onSelected(id),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(
                          AppRadius.input,
                        ),
                      ),
                      child: Icon(icon, color: AppColors.primary),
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
    );
  }
}
