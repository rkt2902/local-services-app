import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_color.dart';
import '../../../../core/widgets/app_filter_chip.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_action_button.dart';

/// 3 secções do formulário de edição do worker, navegadas dentro do mesmo
/// ecrã (sem trocar de rota) via [AppFadeThroughSwitcher].
enum WorkerProfileEditSection { overview, baseLocation, servicesAndTools }

/// Dados de apresentação do formulário de edição do worker.
///
/// A integração (worker_edit_profile_screen.dart) mapeia o `WorkerProfile`
/// real + o estado de rascunho (localização, raio, serviços, ferramentas —
/// editável em várias secções antes de qualquer save) para esta estrutura.
/// Este widget não consulta providers, repositories ou Supabase diretamente.
class WorkerProfileEditViewData {
  const WorkerProfileEditViewData({
    required this.profileId,
    required this.locationSummaryLabel,
    required this.locationNeedsDefinition,
    required this.radiusKm,
    required this.radiusSummaryLabel,
    required this.servicesSummaryLabel,
    required this.toolsSummaryLabel,
    required this.ratingsSummaryLabel,
    required this.baseLocation,
    required this.servicesAndTools,
    this.avatarImage,
  });

  final String profileId;
  final ImageProvider? avatarImage;

  /// Todos os resumos chegam já formatados pela integração.
  final String locationSummaryLabel;
  final bool locationNeedsDefinition;

  final int radiusKm;
  final String radiusSummaryLabel;
  final String servicesSummaryLabel;
  final String toolsSummaryLabel;
  final String ratingsSummaryLabel;

  final WorkerBaseLocationViewData baseLocation;
  final WorkerServicesToolsViewData servicesAndTools;
}

class WorkerBaseLocationViewData {
  const WorkerBaseLocationViewData({
    required this.manualCoordinatesEnabled,
    required this.radiusKm,
    this.isResolvingLocation = false,
    this.resolvedLocationLabel,
    this.resolvedCoordinatesLabel,
    this.errorMessage,
  });

  final bool manualCoordinatesEnabled;
  final bool isResolvingLocation;

  /// Localização e coordenadas já formatadas.
  final String? resolvedLocationLabel;
  final String? resolvedCoordinatesLabel;

  final int radiusKm;

  final String? errorMessage;
}

class WorkerServiceSelectionViewData {
  const WorkerServiceSelectionViewData({
    required this.id,
    required this.label,
    required this.selected,
  });

  final String id;
  final String label;
  final bool selected;
}

class WorkerServicesToolsViewData {
  const WorkerServicesToolsViewData({
    required this.selectedServicesCountLabel,
    required this.services,
    required this.tools,
  });

  /// Ex.: "3 selecionados" — já preparado pela integração.
  final String selectedServicesCountLabel;

  final List<WorkerServiceSelectionViewData> services;
  final List<String> tools;
}

class WorkerProfileEditScreen extends StatelessWidget {
  const WorkerProfileEditScreen({
    super.key,
    required this.dataAsync,
    required this.section,
    required this.onBack,
    required this.onSectionBack,
    required this.onSignOut,
    required this.fullNameController,
    required this.phoneController,
    required this.bioController,
    required this.hourlyRateController,
    required this.onChangePhoto,
    required this.onOpenBaseLocation,
    required this.onOpenServicesAndTools,
    required this.onOpenRatings,
    required this.onSaveOverview,
    required this.addressSearchController,
    required this.latitudeController,
    required this.longitudeController,
    required this.onUseGps,
    required this.onSubmitAddressSearch,
    required this.onToggleManualCoordinates,
    required this.onRadiusChanged,
    required this.onSaveBaseLocation,
    required this.serviceSearchController,
    required this.toolInputController,
    required this.onToggleService,
    required this.onAddTool,
    required this.onRemoveTool,
    required this.onSaveServicesAndTools,
    this.fullNameValidator,
    this.phoneValidator,
    this.onRetry,
  });

  /// null = perfil não encontrado / sessão já não permite resolver um
  /// perfil de worker.
  final AsyncValue<WorkerProfileEditViewData?> dataAsync;

  /// Controlado pelo wrapper — qual das 3 secções está visível.
  final WorkerProfileEditSection section;

  final VoidCallback onBack;
  final VoidCallback onSectionBack;
  final VoidCallback onSignOut;

  final TextEditingController fullNameController;
  final TextEditingController phoneController;
  final TextEditingController bioController;
  final TextEditingController hourlyRateController;
  final String? Function(String?)? fullNameValidator;
  final String? Function(String?)? phoneValidator;

  final VoidCallback onChangePhoto;
  final VoidCallback onOpenBaseLocation;
  final VoidCallback onOpenServicesAndTools;
  final VoidCallback onOpenRatings;
  final Future<bool> Function() onSaveOverview;

  final TextEditingController addressSearchController;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final VoidCallback onUseGps;
  final VoidCallback onSubmitAddressSearch;
  final ValueChanged<bool> onToggleManualCoordinates;
  final ValueChanged<int> onRadiusChanged;
  final Future<bool> Function() onSaveBaseLocation;

  final TextEditingController serviceSearchController;
  final TextEditingController toolInputController;
  final ValueChanged<String> onToggleService;
  final VoidCallback onAddTool;
  final ValueChanged<String> onRemoveTool;
  final Future<bool> Function() onSaveServicesAndTools;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: dataAsync.when(
          loading: () => _WorkerProfileLoading(
            title: _titleForSection(section),
            onBack: section == WorkerProfileEditSection.overview
                ? onBack
                : onSectionBack,
          ),
          error: (_, _) => _WorkerProfileError(
            title: _titleForSection(section),
            onBack: section == WorkerProfileEditSection.overview
                ? onBack
                : onSectionBack,
            onRetry: onRetry,
          ),
          data: (data) {
            if (data == null) {
              return _WorkerProfileNotFound(onSignOut: onSignOut);
            }

            return AppFadeThroughSwitcher(
              switchKey: section,
              duration: const Duration(milliseconds: 220),
              child: switch (section) {
                WorkerProfileEditSection.overview => _WorkerProfileOverview(
                    key: ValueKey('overview_${data.profileId}'),
                    data: data,
                    fullNameController: fullNameController,
                    phoneController: phoneController,
                    bioController: bioController,
                    hourlyRateController: hourlyRateController,
                    fullNameValidator: fullNameValidator,
                    phoneValidator: phoneValidator,
                    onBack: onBack,
                    onSignOut: onSignOut,
                    onChangePhoto: onChangePhoto,
                    onOpenBaseLocation: onOpenBaseLocation,
                    onOpenServicesAndTools: onOpenServicesAndTools,
                    onOpenRatings: onOpenRatings,
                    onSave: onSaveOverview,
                  ),
                WorkerProfileEditSection.baseLocation =>
                  _WorkerBaseLocationEditor(
                    key: ValueKey('location_${data.profileId}'),
                    data: data.baseLocation,
                    addressSearchController: addressSearchController,
                    latitudeController: latitudeController,
                    longitudeController: longitudeController,
                    onBack: onSectionBack,
                    onUseGps: onUseGps,
                    onSubmitAddressSearch: onSubmitAddressSearch,
                    onToggleManualCoordinates: onToggleManualCoordinates,
                    onRadiusChanged: onRadiusChanged,
                    onSave: onSaveBaseLocation,
                  ),
                WorkerProfileEditSection.servicesAndTools =>
                  _WorkerServicesToolsEditor(
                    key: ValueKey('services_${data.profileId}'),
                    data: data.servicesAndTools,
                    serviceSearchController: serviceSearchController,
                    toolInputController: toolInputController,
                    onBack: onSectionBack,
                    onToggleService: onToggleService,
                    onAddTool: onAddTool,
                    onRemoveTool: onRemoveTool,
                    onSave: onSaveServicesAndTools,
                  ),
              },
            );
          },
        ),
      ),
    );
  }

  static String _titleForSection(WorkerProfileEditSection section) {
    return switch (section) {
      WorkerProfileEditSection.overview => 'O meu perfil',
      WorkerProfileEditSection.baseLocation => 'Localização base',
      WorkerProfileEditSection.servicesAndTools => 'Serviços e ferramentas',
    };
  }
}

// -----------------------------------------------------------------------------
// 1. VISTA GERAL
// -----------------------------------------------------------------------------

class _WorkerProfileOverview extends StatefulWidget {
  const _WorkerProfileOverview({
    super.key,
    required this.data,
    required this.fullNameController,
    required this.phoneController,
    required this.bioController,
    required this.hourlyRateController,
    required this.fullNameValidator,
    required this.phoneValidator,
    required this.onBack,
    required this.onSignOut,
    required this.onChangePhoto,
    required this.onOpenBaseLocation,
    required this.onOpenServicesAndTools,
    required this.onOpenRatings,
    required this.onSave,
  });

  final WorkerProfileEditViewData data;

  final TextEditingController fullNameController;
  final TextEditingController phoneController;
  final TextEditingController bioController;
  final TextEditingController hourlyRateController;
  final String? Function(String?)? fullNameValidator;
  final String? Function(String?)? phoneValidator;

  final VoidCallback onBack;
  final VoidCallback onSignOut;
  final VoidCallback onChangePhoto;
  final VoidCallback onOpenBaseLocation;
  final VoidCallback onOpenServicesAndTools;
  final VoidCallback onOpenRatings;

  final Future<bool> Function() onSave;

  @override
  State<_WorkerProfileOverview> createState() => _WorkerProfileOverviewState();
}

class _WorkerProfileOverviewState extends State<_WorkerProfileOverview> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _successVisible = false;
  Timer? _successTimer;

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _successTimer?.cancel();
    setState(() {
      _saving = true;
      _successVisible = false;
    });

    final confirmed = await widget.onSave();

    if (!mounted) return;
    setState(() {
      _saving = false;
      _successVisible = confirmed;
    });
    if (confirmed) {
      _successTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) setState(() => _successVisible = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _ProfileHeader(
              title: 'O meu perfil',
              onBack: widget.onBack,
              trailing: IconButton(
                onPressed: widget.onSignOut,
                tooltip: 'Sair',
                icon: Icon(
                  Icons.logout_rounded,
                  color: AppStatusColor.cancelled.foreground,
                ),
              ),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  key: const PageStorageKey('worker_profile_edit_overview'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  children: [
                    AppStaggeredEntrance(
                      index: 0,
                      child: _AvatarPicker(
                        avatarImage: widget.data.avatarImage,
                        onChangePhoto: widget.onChangePhoto,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppStaggeredEntrance(
                      index: 1,
                      child: AppTextField(
                        controller: widget.fullNameController,
                        label: 'Nome completo *',
                        keyboardType: TextInputType.name,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        validator: widget.fullNameValidator,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 2,
                      child: AppTextField(
                        controller: widget.phoneController,
                        label: 'Telefone *',
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        validator: widget.phoneValidator,
                        suffixIcon: const Icon(
                          Icons.phone_outlined,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 3,
                      child: AppTextField(
                        controller: widget.bioController,
                        label: 'Apresentação (opcional)',
                        textInputAction: TextInputAction.newline,
                        minLines: 2,
                        maxLines: 4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 4,
                      child: AppTextField(
                        controller: widget.hourlyRateController,
                        label: 'Preço/hora (€) — opcional',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        suffixIcon: const Icon(
                          Icons.euro_outlined,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const Divider(height: 1, color: AppColors.divider),
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 5,
                      child: _ProfileSectionRow(
                        icon: Icons.location_off_outlined,
                        title: 'Localização base',
                        summary: widget.data.locationSummaryLabel,
                        warning: widget.data.locationNeedsDefinition,
                        onTap: widget.onOpenBaseLocation,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 6,
                      child: _ProfileSectionRow(
                        icon: Icons.radar_outlined,
                        title: 'Raio de atuação',
                        summary: widget.data.radiusSummaryLabel,
                        onTap: widget.onOpenBaseLocation,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 7,
                      child: _ProfileSectionRow(
                        icon: Icons.grass_outlined,
                        title: 'Serviços que faço',
                        summary: widget.data.servicesSummaryLabel,
                        onTap: widget.onOpenServicesAndTools,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 8,
                      child: _ProfileSectionRow(
                        icon: Icons.handyman_outlined,
                        title: 'Ferramentas',
                        summary: widget.data.toolsSummaryLabel,
                        onTap: widget.onOpenServicesAndTools,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppStaggeredEntrance(
                      index: 9,
                      child: _ProfileSectionRow(
                        icon: Icons.star_border_rounded,
                        title: 'As minhas avaliações',
                        summary: widget.data.ratingsSummaryLabel,
                        trailingIsForward: true,
                        onTap: widget.onOpenRatings,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: PrimaryActionButton(
                label: _saving ? 'A guardar...' : 'Guardar alterações',
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
        Positioned.fill(
          child: AppSuccessFeedback(
            visible: _successVisible,
            message: 'Alterações guardadas com sucesso.',
          ),
        ),
      ],
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.avatarImage, required this.onChangePhoto});

  final ImageProvider? avatarImage;
  final VoidCallback onChangePhoto;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CircleAvatar(
                    backgroundColor: AppColors.primaryContainer,
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? const Icon(
                            Icons.person_outline_rounded,
                            color: AppColors.primary,
                          )
                        : null,
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: 2,
                  child: Material(
                    color: AppColors.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: onChangePhoto,
                      customBorder: const CircleBorder(),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.surface),
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          color: AppColors.surface,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: onChangePhoto,
            child: Text(
              'Alterar foto',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionRow extends StatelessWidget {
  const _ProfileSectionRow({
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
    this.warning = false,
    this.trailingIsForward = false,
  });

  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;
  final bool warning;
  final bool trailingIsForward;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final background =
        warning ? AppStatusColor.waiting.background : AppColors.surface;
    final borderColor =
        warning ? AppStatusColor.waiting.foreground : AppColors.divider;
    final iconColor =
        warning ? AppStatusColor.waiting.foreground : AppColors.textSecondary;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelMedium?.copyWith(
                        color: warning
                            ? AppStatusColor.waiting.foreground
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                trailingIsForward
                    ? Icons.chevron_right_rounded
                    : Icons.expand_more_rounded,
                color: warning
                    ? AppStatusColor.waiting.foreground
                    : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. LOCALIZAÇÃO BASE
// -----------------------------------------------------------------------------

class _WorkerBaseLocationEditor extends StatefulWidget {
  const _WorkerBaseLocationEditor({
    super.key,
    required this.data,
    required this.addressSearchController,
    required this.latitudeController,
    required this.longitudeController,
    required this.onBack,
    required this.onUseGps,
    required this.onSubmitAddressSearch,
    required this.onToggleManualCoordinates,
    required this.onRadiusChanged,
    required this.onSave,
  });

  final WorkerBaseLocationViewData data;

  final TextEditingController addressSearchController;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;

  final VoidCallback onBack;
  final VoidCallback onUseGps;
  final VoidCallback onSubmitAddressSearch;
  final ValueChanged<bool> onToggleManualCoordinates;
  final ValueChanged<int> onRadiusChanged;

  final Future<bool> Function() onSave;

  @override
  State<_WorkerBaseLocationEditor> createState() =>
      _WorkerBaseLocationEditorState();
}

class _WorkerBaseLocationEditorState extends State<_WorkerBaseLocationEditor> {
  bool _saving = false;
  bool _successVisible = false;
  Timer? _successTimer;

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    _successTimer?.cancel();
    setState(() {
      _saving = true;
      _successVisible = false;
    });

    final confirmed = await widget.onSave();

    if (!mounted) return;
    setState(() {
      _saving = false;
      _successVisible = confirmed;
    });
    if (confirmed) {
      _successTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) setState(() => _successVisible = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _ProfileHeader(title: 'Localização base', onBack: widget.onBack),
            Expanded(
              child: ListView(
                key: const PageStorageKey('worker_profile_base_location'),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  AppStaggeredEntrance(
                    index: 0,
                    child: _GpsButton(
                      isLoading: widget.data.isResolvingLocation,
                      onPressed:
                          widget.data.isResolvingLocation ? null : widget.onUseGps,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _OrDivider(),
                  const SizedBox(height: AppSpacing.md),
                  AppStaggeredEntrance(
                    index: 1,
                    child: _AddressSearchField(
                      controller: widget.addressSearchController,
                      isResolving: widget.data.isResolvingLocation,
                      onSearch: widget.onSubmitAddressSearch,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 2,
                    child: _ManualCoordinatesCard(
                      enabled: widget.data.manualCoordinatesEnabled,
                      latitudeController: widget.latitudeController,
                      longitudeController: widget.longitudeController,
                      onChanged: widget.onToggleManualCoordinates,
                    ),
                  ),
                  if (widget.data.resolvedLocationLabel != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 3,
                      child: _ResolvedLocationCard(
                        locationLabel: widget.data.resolvedLocationLabel!,
                        coordinatesLabel: widget.data.resolvedCoordinatesLabel,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  AppStaggeredEntrance(
                    index: 4,
                    child: _RadiusSlider(
                      radiusKm: widget.data.radiusKm,
                      onChanged: widget.onRadiusChanged,
                    ),
                  ),
                  if (widget.data.errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _InlineError(message: widget.data.errorMessage!),
                  ],
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: PrimaryActionButton(
                label: _saving ? 'A guardar...' : 'Guardar alterações',
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
        Positioned.fill(
          child: AppSuccessFeedback(
            visible: _successVisible,
            message: 'Localização guardada com sucesso.',
          ),
        ),
      ],
    );
  }
}

class _GpsButton extends StatelessWidget {
  const _GpsButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                const Icon(Icons.gps_fixed_rounded, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                isLoading ? 'A obter localização...' : 'Atualizar pelo GPS',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.divider)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            'ou',
            style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.divider)),
      ],
    );
  }
}

/// Campo de morada com pesquisa dedicada. NÃO usa `AppSearchField` — esse
/// widget não tem slot para o `suffixIcon` alternar entre lupa e spinner
/// enquanto o geocoding corre, que este campo precisa de preservar.
class _AddressSearchField extends StatelessWidget {
  const _AddressSearchField({
    required this.controller,
    required this.isResolving,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool isResolving;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return TextField(
      controller: controller,
      keyboardType: TextInputType.streetAddress,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
      style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: 'Pesquisar morada',
        labelStyle:
            textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
        prefixIcon: const Icon(Icons.place_outlined, color: AppColors.textSecondary),
        suffixIcon: isResolving
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.search, color: AppColors.primary),
                onPressed: onSearch,
              ),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
    );
  }
}

class _ManualCoordinatesCard extends StatelessWidget {
  const _ManualCoordinatesCard({
    required this.enabled,
    required this.latitudeController,
    required this.longitudeController,
    required this.onChanged,
  });

  final bool enabled;
  final TextEditingController latitudeController;
  final TextEditingController longitudeController;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.explore_outlined, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Introduzir coordenadas manualmente',
                  style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              Switch(
                value: enabled,
                onChanged: onChanged,
                activeTrackColor: AppColors.primary,
                activeThumbColor: AppColors.surface,
              ),
            ],
          ),
          AppFadeThroughSwitcher(
            switchKey: enabled,
            duration: const Duration(milliseconds: 180),
            child: enabled
                ? Padding(
                    key: const ValueKey('coordinates_visible'),
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: latitudeController,
                            label: 'Latitude',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: AppTextField(
                            controller: longitudeController,
                            label: 'Longitude',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            textInputAction: TextInputAction.done,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('coordinates_hidden')),
          ),
        ],
      ),
    );
  }
}

class _ResolvedLocationCard extends StatelessWidget {
  const _ResolvedLocationCard({
    required this.locationLabel,
    required this.coordinatesLabel,
  });

  final String locationLabel;
  final String? coordinatesLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on_outlined, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locationLabel,
                  style: textTheme.titleMedium?.copyWith(color: AppColors.primary),
                ),
                if (coordinatesLabel != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    coordinatesLabel!,
                    style: textTheme.labelMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            Icons.check_circle_outline_rounded,
            color: AppStatusColor.success.foreground,
          ),
        ],
      ),
    );
  }
}

/// Slider contínuo (1–50 km, qualquer inteiro) — NÃO chips discretos. O
/// worker já usa este range com esta precisão hoje; chips por opção fixa
/// perderiam granularidade real.
class _RadiusSlider extends StatelessWidget {
  const _RadiusSlider({required this.radiusKm, required this.onChanged});

  final int radiusKm;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Raio de atuação',
                style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
              ),
            ),
            Text(
              '$radiusKm km',
              style: textTheme.titleMedium?.copyWith(color: AppColors.primary),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.divider,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withValues(alpha: 0.12),
            valueIndicatorColor: AppColors.primary,
          ),
          child: Slider(
            value: radiusKm.toDouble(),
            min: 1,
            max: 50,
            divisions: 49,
            label: '$radiusKm km',
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 3. SERVIÇOS & FERRAMENTAS
// -----------------------------------------------------------------------------

class _WorkerServicesToolsEditor extends StatefulWidget {
  const _WorkerServicesToolsEditor({
    super.key,
    required this.data,
    required this.serviceSearchController,
    required this.toolInputController,
    required this.onBack,
    required this.onToggleService,
    required this.onAddTool,
    required this.onRemoveTool,
    required this.onSave,
  });

  final WorkerServicesToolsViewData data;
  final TextEditingController serviceSearchController;
  final TextEditingController toolInputController;

  final VoidCallback onBack;
  final ValueChanged<String> onToggleService;
  final VoidCallback onAddTool;
  final ValueChanged<String> onRemoveTool;

  final Future<bool> Function() onSave;

  @override
  State<_WorkerServicesToolsEditor> createState() =>
      _WorkerServicesToolsEditorState();
}

class _WorkerServicesToolsEditorState
    extends State<_WorkerServicesToolsEditor> {
  bool _saving = false;
  bool _successVisible = false;
  Timer? _successTimer;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.serviceSearchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    widget.serviceSearchController.removeListener(_handleSearchChanged);
    _successTimer?.cancel();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() => _query = widget.serviceSearchController.text.trim().toLowerCase());
  }

  Future<void> _save() async {
    if (_saving) return;

    _successTimer?.cancel();
    setState(() {
      _saving = true;
      _successVisible = false;
    });

    final confirmed = await widget.onSave();

    if (!mounted) return;
    setState(() {
      _saving = false;
      _successVisible = confirmed;
    });
    if (confirmed) {
      _successTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) setState(() => _successVisible = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final visibleServices = _query.isEmpty
        ? widget.data.services
        : widget.data.services
            .where((s) => s.label.toLowerCase().contains(_query))
            .toList();

    return Stack(
      children: [
        Column(
          children: [
            _ProfileHeader(title: 'Serviços e ferramentas', onBack: widget.onBack),
            Expanded(
              child: ListView(
                key: const PageStorageKey('worker_profile_services_tools'),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  AppStaggeredEntrance(
                    index: 0,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Serviços que faço',
                            style: textTheme.titleMedium
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                        Text(
                          widget.data.selectedServicesCountLabel,
                          style: textTheme.labelMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppStaggeredEntrance(
                    index: 1,
                    child: AppSearchField(
                      controller: widget.serviceSearchController,
                      hintText: 'Procurar serviço...',
                      onChanged: (_) {},
                      onClear: () {
                        widget.serviceSearchController.clear();
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 2,
                    child: visibleServices.isEmpty
                        ? const _NoServicesMatch()
                        : Wrap(
                            spacing: AppSpacing.xs,
                            runSpacing: AppSpacing.xs,
                            children: visibleServices.map((service) {
                              return AppFilterChip(
                                label: service.label,
                                selected: service.selected,
                                showCheckmark: service.selected,
                                onPressed: () => widget.onToggleService(service.id),
                              );
                            }).toList(),
                          ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Divider(color: AppColors.divider),
                  const SizedBox(height: AppSpacing.sm),
                  AppStaggeredEntrance(
                    index: 3,
                    child: Text(
                      'Ferramentas que tenho',
                      style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppStaggeredEntrance(
                    index: 4,
                    child: Row(
                      children: [
                        Expanded(
                          child: _ToolInput(
                            controller: widget.toolInputController,
                            onSubmitted: widget.onAddTool,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        _AddToolButton(onPressed: widget.onAddTool),
                      ],
                    ),
                  ),
                  if (widget.data.tools.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AppStaggeredEntrance(
                      index: 5,
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: widget.data.tools.map((tool) {
                          return _ToolChip(
                            label: tool,
                            onRemove: () => widget.onRemoveTool(tool),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: PrimaryActionButton(
                label: _saving ? 'A guardar...' : 'Guardar alterações',
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
        Positioned.fill(
          child: AppSuccessFeedback(
            visible: _successVisible,
            message: 'Alterações guardadas com sucesso.',
          ),
        ),
      ],
    );
  }
}

class _ToolInput extends StatelessWidget {
  const _ToolInput({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: 'Adicionar ferramenta',
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => onSubmitted(),
    );
  }
}

class _AddToolButton extends StatelessWidget {
  const _AddToolButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: const SizedBox(
          width: 56,
          height: 56,
          child: Icon(Icons.add_rounded, color: AppColors.surface),
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InputChip(
      label: Text(
        label,
        style: textTheme.labelMedium?.copyWith(color: AppColors.textPrimary),
      ),
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      deleteIconColor: AppColors.textSecondary,
      onDeleted: onRemove,
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.divider),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
    );
  }
}

class _NoServicesMatch extends StatelessWidget {
  const _NoServicesMatch();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        'Nenhum serviço corresponde à pesquisa.',
        style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SHARED LOCAL
// -----------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.title, required this.onBack, this.trailing});

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Voltar',
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              title,
              style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppStatusColor.cancelled.background,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Text(
        message,
        style: textTheme.bodyMedium?.copyWith(color: AppStatusColor.cancelled.foreground),
      ),
    );
  }
}

class _WorkerProfileLoading extends StatelessWidget {
  const _WorkerProfileLoading({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProfileHeader(title: title, onBack: onBack),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Center(
                child: AppSkeletonShimmer(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ...List.generate(
                4,
                (_) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppSkeletonShimmer(
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.input),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkerProfileError extends StatelessWidget {
  const _WorkerProfileError({
    required this.title,
    required this.onBack,
    required this.onRetry,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        _ProfileHeader(title: title, onBack: onBack),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppStatusColor.cancelled.background,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.cloud_off_outlined,
                      color: AppStatusColor.cancelled.foreground,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Não foi possível carregar',
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Verifica a ligação e tenta novamente.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: onRetry,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.input),
                        ),
                      ),
                      child: Text(
                        'Tentar novamente',
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkerProfileNotFound extends StatelessWidget {
  const _WorkerProfileNotFound({required this.onSignOut});

  final VoidCallback onSignOut;

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
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppStatusColor.neutral.background,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.person_off_outlined,
                  color: AppStatusColor.neutral.foreground,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Perfil não encontrado',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'A tua sessão pode já não ser válida. Entra novamente.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryActionButton(label: 'Sair e voltar ao login', onPressed: onSignOut),
            ],
          ),
        ),
      ),
    );
  }
}
