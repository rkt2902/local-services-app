import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_status_color.dart';
import '../../../core/utils/error_utils.dart';
import '../../../core/widgets/app_filter_chip.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_status_badge.dart';
import '../application/admin_labels.dart';
import '../application/admin_providers.dart';
import '../data/admin_account_models.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_stat_widgets.dart';

/// Mapa (`/admin/mapa`, fase C): pedidos ativos e concluídos há pouco, e
/// jardineiros com o raio onde recebem pedidos. As camadas ligam-se e
/// desligam-se; tocar num ponto mostra o resumo e o atalho para a ficha.
/// Abrir o mapa fica no Registo (como as outras consultas).
class AdminMapPage extends ConsumerStatefulWidget {
  const AdminMapPage({super.key});

  @override
  ConsumerState<AdminMapPage> createState() => _AdminMapPageState();
}

class _AdminMapPageState extends ConsumerState<AdminMapPage> {
  Set<AdminMapLayer> _layers = {
    AdminMapLayer.openJobs,
    AdminMapLayer.activeJobs,
    AdminMapLayer.workers,
  };
  AdminMapPoint? _selected;

  void _toggle(AdminMapLayer layer) {
    setState(() {
      _layers = {..._layers};
      if (!_layers.remove(layer)) _layers.add(layer);
      final selected = _selected;
      if (selected != null &&
          adminVisibleMapPoints([selected], _layers).isEmpty) {
        _selected = null;
      }
    });
  }

  void _open(AdminMapPoint point) => context.go(
    point.isJob ? '/admin/pedidos/${point.id}' : '/admin/workers/${point.id}',
  );

  @override
  Widget build(BuildContext context) {
    final pointsAsync = ref.watch(adminMapPointsProvider);
    return pointsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: AdminLoadingBlocks(count: 1, height: AppSizes.adminMapMinHeight),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppInlineError(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(adminMapPointsProvider),
        ),
      ),
      data: (points) => AdminMapView(
        points: points,
        layers: _layers,
        selected: _selected,
        onToggle: _toggle,
        onSelect: (p) => setState(() => _selected = p),
        onOpen: _open,
        onRefresh: () => ref.invalidate(adminMapPointsProvider),
      ),
    );
  }
}

/// Vista do mapa sem Riverpod. [showTiles] `false` nos testes (sem rede).
class AdminMapView extends StatelessWidget {
  const AdminMapView({
    required this.points,
    required this.layers,
    required this.selected,
    required this.onToggle,
    required this.onSelect,
    required this.onOpen,
    required this.onRefresh,
    this.showTiles = true,
    super.key,
  });

  final List<AdminMapPoint> points;
  final Set<AdminMapLayer> layers;
  final AdminMapPoint? selected;
  final ValueChanged<AdminMapLayer> onToggle;
  final ValueChanged<AdminMapPoint?> onSelect;
  final ValueChanged<AdminMapPoint> onOpen;
  final VoidCallback onRefresh;
  final bool showTiles;

  static const _portugal = LatLng(39.6, -8.0);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final visible = adminVisibleMapPoints(points, layers);
    final workers = visible.where((p) => !p.isJob).toList();
    final jobs = visible.where((p) => p.isJob).toList();
    final showRadius =
        layers.contains(AdminMapLayer.radius) &&
        layers.contains(AdminMapLayer.workers);
    final summary = adminMapSummary(points);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppStaggeredEntrance(
            index: 0,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Mapa',
                    style: textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: onRefresh,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          AppStaggeredEntrance(
            index: 1,
            child: Text(
              summary,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppStaggeredEntrance(
            index: 2,
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final layer in AdminMapLayer.values)
                  AppFilterChip(
                    label: layer.label,
                    selected: layers.contains(layer),
                    showCheckmark: true,
                    onPressed: () => onToggle(layer),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: AppStaggeredEntrance(
              index: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: _portugal,
                    initialZoom: 6.5,
                    initialCameraFit: visible.length > 1
                        ? CameraFit.coordinates(
                            coordinates: [
                              for (final p in visible) LatLng(p.lat, p.lng),
                            ],
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            maxZoom: 12,
                          )
                        : null,
                    onTap: (_, _) => onSelect(null),
                  ),
                  children: [
                    if (showTiles)
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'pt.projardim.app',
                      ),
                    if (showRadius)
                      CircleLayer(
                        circles: [
                          for (final w in workers)
                            if (w.radiusKm != null)
                              CircleMarker(
                                point: LatLng(w.lat, w.lng),
                                radius: w.radiusKm! * 1000,
                                useRadiusInMeter: true,
                                color: AppColors.primary.withValues(
                                  alpha: 0.06,
                                ),
                                borderColor: AppColors.primary.withValues(
                                  alpha: 0.35,
                                ),
                                borderStrokeWidth: 1,
                              ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final p in [...workers, ...jobs])
                          Marker(
                            point: LatLng(p.lat, p.lng),
                            width: AppSizes.minTapTarget,
                            height: AppSizes.minTapTarget,
                            child: _MapDot(
                              point: p,
                              selected: selected?.id == p.id,
                              onTap: () => onSelect(p),
                            ),
                          ),
                      ],
                    ),
                    if (showTiles)
                      SimpleAttributionWidget(
                        backgroundColor: AppColors.surface,
                        onTap: () => launchUrl(
                          Uri.parse('https://www.openstreetmap.org/copyright'),
                          mode: LaunchMode.externalApplication,
                        ),
                        source: Text(
                          'OpenStreetMap contributors',
                          style: textTheme.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: AppMotionDuration.screen,
            child: selected == null
                ? const SizedBox.shrink()
                : Padding(
                    key: ValueKey(selected!.id),
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: AdminMapPointCard(
                      point: selected!,
                      onOpen: () => onOpen(selected!),
                      onClose: () => onSelect(null),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// "12 pedidos abertos · 4 em curso · 9 concluídos · 30 jardineiros".
String adminMapSummary(List<AdminMapPoint> points) {
  var open = 0, active = 0, done = 0, workers = 0, suspended = 0;
  for (final p in points) {
    if (!p.isJob) {
      workers++;
      if (p.status == 'suspended') suspended++;
    } else if (p.status == 'open') {
      open++;
    } else if (p.status == 'completed') {
      done++;
    } else {
      active++;
    }
  }
  return [
    '$open pedidos abertos',
    '$active em curso',
    '$done concluídos (30 dias)',
    '$workers jardineiros${suspended > 0 ? ' ($suspended suspensos)' : ''}',
  ].join(' · ');
}

/// Cor do ponto: pedidos pelo estado, jardineiros a verde (vermelho se
/// suspensos).
AppStatusColor adminMapPointTone(AdminMapPoint p) {
  if (!p.isJob) {
    return p.status == 'suspended'
        ? AppStatusColor.cancelled
        : AppStatusColor.success;
  }
  return adminMapJobStatus(p.status).$2;
}

class _MapDot extends StatelessWidget {
  const _MapDot({
    required this.point,
    required this.selected,
    required this.onTap,
  });

  final AdminMapPoint point;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = adminMapPointTone(point);
    final size = selected ? AppSizes.adminMapDot * 1.5 : AppSizes.adminMapDot;
    return Semantics(
      button: true,
      label: point.isJob
          ? 'Pedido ${point.label}'
          : 'Jardineiro ${point.label}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: AppMotionDuration.fast,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: tone.foreground,
              shape: point.isJob ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: point.isJob
                  ? null
                  : BorderRadius.circular(AppRadius.input),
              border: Border.all(
                color: AppColors.surface,
                width: AppSizes.adminMapDotBorder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminMapPointCard extends StatelessWidget {
  const AdminMapPointCard({
    required this.point,
    required this.onOpen,
    required this.onClose,
    super.key,
  });

  final AdminMapPoint point;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = point;
    final (statusLabel, statusColor) = p.isJob
        ? adminMapJobStatus(p.status)
        : (
            p.status == 'suspended' ? 'Suspenso' : 'Ativo',
            adminMapPointTone(p),
          );
    final details = p.isJob
        ? [
            if (p.service != null) p.service!,
            'publicado ${adminRelativeDateLabel(p.createdAt)}',
            adminShortId(p.id),
          ]
        : [
            if (p.radiusKm != null) 'raio ${p.radiusKm} km',
            'plano ${adminPlanLabel(p.plan)}',
            'desde ${adminDateLabel(p.createdAt)}',
          ];
    return AdminPanelCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      p.isJob ? 'Pedido · ${p.label}' : p.label,
                      style: textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    AppStatusBadge(
                      label: statusLabel,
                      statusColor: statusColor,
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  details.join(' · '),
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onOpen, child: const Text('Abrir ficha')),
          IconButton(
            tooltip: 'Fechar',
            onPressed: onClose,
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Grátis", "Pro", "Pro+".
String adminPlanLabel(String? plan) => switch (plan) {
  'pro' => 'Pro',
  'pro_plus' => 'Pro+',
  _ => 'Grátis',
};
