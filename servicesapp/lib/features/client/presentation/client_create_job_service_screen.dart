import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_step_progress.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../../jobs/application/job_providers.dart';
import '../application/client_create_job_wizard_provider.dart';

/// Passo 1/3 de "Criar pedido" — escolha do tipo de serviço.
///
/// `serviceTypesProvider` é o mesmo provider já usado do lado do worker
/// (re-exportado por `jobs/application/job_providers.dart`).
class ClientCreateJobServiceScreen extends ConsumerStatefulWidget {
  const ClientCreateJobServiceScreen({super.key});

  @override
  ConsumerState<ClientCreateJobServiceScreen> createState() {
    return _ClientCreateJobServiceScreenState();
  }
}

class _ClientCreateJobServiceScreenState
    extends ConsumerState<ClientCreateJobServiceScreen> {
  late final TextEditingController _searchController;

  String? _selectedServiceTypeId;

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
    context.push('/client/create-job/schedule');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final serviceTypesAsync = ref.watch(serviceTypesProvider);
    final query = _searchController.text.trim().toLowerCase();

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
            child: AppStepProgress(currentStep: 1, totalSteps: 3),
          ),
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
                  Text(
                    'Categorias',
                    style: textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 2,
                    child: serviceTypesAsync.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.lg),
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
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
                      final filtered = query.isEmpty
                          ? serviceTypes
                          : serviceTypes
                              .where((s) =>
                                  s.name.toLowerCase().contains(query))
                              .toList();

                      if (filtered.isEmpty) {
                        return Text(
                          'Nenhum serviço encontrado.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        );
                      }

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: AppSpacing.xs,
                          mainAxisSpacing: AppSpacing.xs,
                          childAspectRatio: 0.95,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final serviceType = filtered[index];
                          return ClientServiceTypeTile(
                            id: serviceType.id,
                            label: serviceType.name,
                            // MVP só tem a categoria "Jardinagem" — ícone
                            // genérico único, mesma decisão já tomada do
                            // lado do worker (worker_available_jobs_screen).
                            icon: Icons.yard_outlined,
                            selected:
                                _selectedServiceTypeId == serviceType.id,
                            onSelected: (id) {
                              setState(() => _selectedServiceTypeId = id);
                            },
                          );
                        },
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
