import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_back_navigation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/app_log.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/primary_action_button.dart';
import '../application/fuel_usage_form.dart';
import '../application/fuel_usage_providers.dart';
import '../data/fuel_usage_model.dart';
import 'widgets/worker_setup_step_header.dart';

/// De onde se abre o ecrã de combustível.
enum FuelUsageScreenMode {
  /// Passo 2 de 2 do registo: "Entrar na app" e "Saltar por agora".
  onboarding,

  /// Perfil: "Guardar" e voltar.
  profile,
}

/// Consumo de combustível do Profissional (0084): tipos e litros por mês,
/// com uma linha por tipo. Opcional; serve para estatística agregada com
/// parceiros (cartão frota) e não aparece no perfil público.
class WorkerFuelUsageScreen extends ConsumerStatefulWidget {
  const WorkerFuelUsageScreen({required this.mode, super.key});

  final FuelUsageScreenMode mode;

  @override
  ConsumerState<WorkerFuelUsageScreen> createState() =>
      _WorkerFuelUsageScreenState();
}

class _WorkerFuelUsageScreenState extends ConsumerState<WorkerFuelUsageScreen> {
  final List<FuelUsageRow> _rows = [];
  final Map<int, TextEditingController> _controllers = {};
  int _nextKey = 0;
  bool _loaded = false;
  bool _saving = false;
  bool _whyOpen = false;

  bool get _onboarding => widget.mode == FuelUsageScreenMode.onboarding;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _addRow({String? fuelTypeId, String litersText = ''}) {
    final row = FuelUsageRow(
        key: _nextKey++, fuelTypeId: fuelTypeId, litersText: litersText);
    _rows.add(row);
    _controllers[row.key] = TextEditingController(text: litersText);
  }

  /// Uma vez, quando chegam as respostas gravadas: preenche as linhas (ou
  /// deixa uma vazia).
  void _loadFrom(List<FuelUsageEntry> saved) {
    if (_loaded) return;
    _loaded = true;
    for (final e in saved) {
      _addRow(fuelTypeId: e.fuelTypeId, litersText: fuelLitersText(e.litersPerMonth));
    }
    if (_rows.isEmpty) _addRow();
  }

  void _removeRow(FuelUsageRow row) {
    setState(() {
      _rows.remove(row);
      _controllers.remove(row.key)?.dispose();
    });
  }

  Future<void> _save(List<FuelType> types) async {
    if (fuelUsageMissingLabel(_rows, types) != null) return;
    final entries = fuelUsageEntries(_rows);
    // No registo, sem nada preenchido é o mesmo que saltar.
    if (_onboarding && entries.isEmpty) {
      _finish(saved: false);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(fuelUsageRepositoryProvider).saveMyUsage(entries);
      if (!mounted) return;
      _finish(saved: true);
    } catch (e) {
      appLog('[FuelUsage] ${e.runtimeType}: $e');
      if (!mounted) return;
      AppToast.of(context).error(friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Regra T4: navegar, depois o aviso, depois invalidar.
  void _finish({required bool saved}) {
    final toast = AppToast.of(context);
    if (_onboarding) {
      context.go('/worker/home');
    } else {
      goBackOrToRoleHome(context);
      if (saved) toast.show('Consumo de combustível guardado.');
    }
    if (saved) ref.invalidate(myFuelUsageProvider);
  }

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(fuelTypesProvider);
    final savedAsync = ref.watch(myFuelUsageProvider);
    final textTheme = Theme.of(context).textTheme;

    final types = typesAsync.value;
    final saved = savedAsync.value;
    final ready = types != null && saved != null;
    if (ready) _loadFrom(saved);
    final error = typesAsync.error ?? savedAsync.error;

    final missing = ready ? fuelUsageMissingLabel(_rows, types) : null;
    final hasAny = _rows.any((r) => !r.isEmpty);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_onboarding)
              WorkerSetupStepHeader(
                step: 2,
                totalSteps: 2,
                onBack: context.canPop() ? context.pop : null,
              )
            else
              const Padding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.s10, AppSpacing.xs, AppSpacing.lg, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppBackButton(),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppStaggeredEntrance(
                      index: 0,
                      child: _Intro(
                        whyOpen: _whyOpen,
                        onWhyPressed: () => setState(() => _whyOpen = !_whyOpen),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Combustíveis',
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (error != null)
                      Text(
                        'Não foi possível carregar os combustíveis: '
                        '${friendlyError(error)}',
                        style: textTheme.bodyMedium?.copyWith(
                            color: AppStatusColor.cancelled.foreground),
                      )
                    else if (!ready)
                      AppSkeletonShimmer(
                        child: Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                        ),
                      )
                    else ...[
                      for (var i = 0; i < _rows.length; i++)
                        Padding(
                          key: ValueKey(_rows[i].key),
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppStaggeredEntrance(
                            index: 1 + i,
                            child: _FuelRowCard(
                              number: i + 1,
                              row: _rows[i],
                              types: types,
                              takenIds: {
                                for (final r in _rows)
                                  if (r != _rows[i] && r.fuelTypeId != null)
                                    r.fuelTypeId!,
                              },
                              controller: _controllers[_rows[i].key]!,
                              onRemove: _rows.length > 1
                                  ? () => _removeRow(_rows[i])
                                  : null,
                              onFuelPressed: (id) => setState(() {
                                final row = _rows[i];
                                row.fuelTypeId =
                                    row.fuelTypeId == id ? null : id;
                              }),
                              onLitersChanged: (text) =>
                                  setState(() => _rows[i].litersText = text),
                            ),
                          ),
                        ),
                      if (_rows.length < types.length)
                        _AddRowButton(
                          onPressed: () => setState(() => _addRow()),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_saving && (missing != null || (_onboarding && !hasAny))) ...[
                    Text(
                      missing ?? 'Opcional. Pode preencher mais tarde no Perfil.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  PrimaryActionButton(
                    label: _onboarding ? 'Entrar na app' : 'Guardar',
                    isLoading: _saving,
                    onPressed: ready && missing == null && !_saving
                        ? () => _save(types)
                        : null,
                  ),
                  if (_onboarding)
                    TextButton(
                      onPressed: _saving ? null : () => _finish(saved: false),
                      child: const Text('Saltar por agora'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ícone, pergunta e "Porque pedimos isto?" (abre e fecha).
class _Intro extends StatelessWidget {
  const _Intro({required this.whyOpen, required this.onWhyPressed});

  final bool whyOpen;
  final VoidCallback onWhyPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = disableAnimations ? Duration.zero : AppMotionDuration.fast;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: AppSizes.stepHeroIconBox,
          height: AppSizes.stepHeroIconBox,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: const Icon(Icons.local_gas_station_outlined,
              size: AppSizes.stepHeroIcon, color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Quanto combustível gasta por mês?',
          style: textTheme.displaySmall?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Um valor aproximado chega. Pode alterar mais tarde no Perfil.',
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          button: true,
          expanded: whyOpen,
          child: InkWell(
            onTap: onWhyPressed,
            borderRadius: BorderRadius.circular(AppRadius.input),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: AppSizes.socialLogo, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.s6),
                  Text(
                    'Porque pedimos isto?',
                    style: textTheme.labelLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  AnimatedRotation(
                    turns: whyOpen ? 0.5 : 0,
                    duration: duration,
                    curve: AppMotionCurve.standard,
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: duration,
          curve: AppMotionCurve.standard,
          alignment: Alignment.topCenter,
          child: whyOpen
              ? Container(
                  margin: const EdgeInsets.only(top: AppSpacing.xs),
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(
                          color: AppColors.primaryContainer, width: 2),
                    ),
                  ),
                  child: Text(
                    'Juntamos estes valores de forma anónima para negociar '
                    'descontos com parceiros, como o cartão frota. Não '
                    'aparecem no seu perfil.',
                    style: textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Um combustível: chips dos tipos, litros por mês e remover.
class _FuelRowCard extends StatelessWidget {
  const _FuelRowCard({
    required this.number,
    required this.row,
    required this.types,
    required this.takenIds,
    required this.controller,
    required this.onFuelPressed,
    required this.onLitersChanged,
    this.onRemove,
  });

  final int number;
  final FuelUsageRow row;
  final List<FuelType> types;

  /// Tipos já escolhidos noutras linhas (cada tipo só uma vez).
  final Set<String> takenIds;
  final TextEditingController controller;
  final ValueChanged<String> onFuelPressed;
  final ValueChanged<String> onLitersChanged;

  /// `null` esconde o botão (com uma só linha não há o que remover).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: AppSizes.headerIconButton,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Combustível $number',
                    style: textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Remover combustível $number',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final t in types)
                _ChipWithState(
                  enabled: !takenIds.contains(t.id),
                  child: AppFilterChip(
                    label: t.name,
                    leadingIcon: t.isOil
                        ? Icons.water_drop_outlined
                        : Icons.local_gas_station_outlined,
                    selected: row.fuelTypeId == t.id,
                    onPressed: () => onFuelPressed(t.id),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xxs),
            child: AppTextField(
              controller: controller,
              label: 'Litros por mês',
              hintText: 'Ex.: 60',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(7),
              ],
              suffixText: 'L/mês',
              onChanged: onLitersChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tipo já escolhido noutra linha: fica esbatido e não responde.
class _ChipWithState extends StatelessWidget {
  const _ChipWithState({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (enabled) return child;
    return Semantics(
      enabled: false,
      child: IgnorePointer(child: Opacity(opacity: 0.4, child: child)),
    );
  }
}

/// "+ Adicionar outro combustível", tracejado como no design.
class _AddRowButton extends StatelessWidget {
  const _AddRowButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Adicionar outro combustível'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSizes.compactButtonHeight),
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.agendaAppBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
    );
  }
}
