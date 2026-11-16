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
import '../data/admin_partner_models.dart';
import 'widgets/admin_panel_widgets.dart';
import 'widgets/admin_partner_marker.dart';
import 'widgets/admin_stat_widgets.dart';

/// Mapa (`/admin/mapa`, fase C): pedidos ativos e concluídos há pouco, e
/// jardineiros com o raio onde recebem pedidos. As camadas ligam-se e
/// desligam-se; tocar num ponto mostra o resumo e o atalho para a ficha.
/// Abrir o mapa fica no Registo (como as outras consultas).
///
/// Desde a 0082: zonas sem resposta, densidade de jardineiros (quadrados
/// de 10 km, pedidos de 90 dias) e parceiros (os que têm localização). As
/// zonas e os parceiros só se pedem quando a camada está ligada.
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
  AdminMapZone? _selectedZone;
  AdminPartner? _selectedPartner;
  final _map = MapController();

  void _toggle(AdminMapLayer layer) {
    setState(() {
      _layers = {..._layers};
      if (!_layers.remove(layer)) _layers.add(layer);
      final selected = _selected;
      if (selected != null &&
          adminVisibleMapPoints([selected], _layers).isEmpty) {
        _selected = null;
      }
      if (!_layers.any((l) => l.isZone)) _selectedZone = null;
      if (!_layers.contains(AdminMapLayer.partners)) _selectedPartner = null;
    });
  }

  void _select({
    AdminMapPoint? point,
    AdminMapZone? zone,
    AdminPartner? partner,
  }) => setState(() {
    _selected = point;
    _selectedZone = zone;
    _selectedPartner = partner;
  });

  void _focusZone(AdminMapZone zone) {
    _select(zone: zone);
    try {
      _map.move(LatLng(zone.centerLat, zone.centerLng), 11);
    } catch (_) {
      // Mapa ainda por desenhar.
    }
  }

  void _open(AdminMapPoint point) => context.go(
    point.isJob ? '/admin/pedidos/${point.id}' : '/admin/workers/${point.id}',
  );

  @override
  Widget build(BuildContext context) {
    final pointsAsync = ref.watch(adminMapPointsProvider);
    final showZones = _layers.any((l) => l.isZone);
    final zonesAsync = showZones ? ref.watch(adminMapZonesProvider) : null;
    final partnersAsync = _layers.contains(AdminMapLayer.partners)
        ? ref.watch(adminPartnersProvider)
        : null;
    final extrasLoading =
        (zonesAsync?.isLoading ?? false) || (partnersAsync?.isLoading ?? false);
    final extrasError = zonesAsync?.error ?? partnersAsync?.error;
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
        zones: zonesAsync?.asData?.value ?? const [],
        partners: partnersAsync?.asData?.value ?? const [],
        extrasNote: extrasError != null
            ? friendlyError(extrasError)
            : extrasLoading
            ? 'A carregar zonas e parceiros…'
            : null,
        layers: _layers,
        selected: _selected,
        selectedZone: _selectedZone,
        selectedPartner: _selectedPartner,
        mapController: _map,
        onToggle: _toggle,
        onSelect: (p) => _select(point: p),
        onSelectZone: (z) => _select(zone: z),
        onFocusZone: _focusZone,
        onSelectPartner: (p) => _select(partner: p),
        onOpen: _open,
        onOpenPartners: () => context.go('/admin/parceiros'),
        onRefresh: () {
          ref.invalidate(adminMapPointsProvider);
          ref.invalidate(adminMapZonesProvider);
          ref.invalidate(adminPartnersProvider);
        },
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
    this.zones = const [],
    this.partners = const [],
    this.extrasNote,
    this.selectedZone,
    this.selectedPartner,
    this.mapController,
    this.onSelectZone,
    this.onFocusZone,
    this.onSelectPartner,
    this.onOpenPartners,
    this.showTiles = true,
    super.key,
  });

  final List<AdminMapPoint> points;
  final List<AdminMapZone> zones;
  final List<AdminPartner> partners;

  /// "A carregar…" ou o erro das zonas e dos parceiros (o resto do mapa
  /// funciona na mesma).
  final String? extrasNote;
  final Set<AdminMapLayer> layers;
  final AdminMapPoint? selected;
  final AdminMapZone? selectedZone;
  final AdminPartner? selectedPartner;
  final MapController? mapController;
  final ValueChanged<AdminMapLayer> onToggle;
  final ValueChanged<AdminMapPoint?> onSelect;
  final ValueChanged<AdminMapZone>? onSelectZone;

  /// Escolher uma zona da lista "Zonas a reforçar" (centra o mapa).
  final ValueChanged<AdminMapZone>? onFocusZone;
  final ValueChanged<AdminPartner>? onSelectPartner;
  final ValueChanged<AdminMapPoint> onOpen;
  final VoidCallback? onOpenPartners;
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
    final showUnanswered = layers.contains(AdminMapLayer.unanswered);
    final showDensity = layers.contains(AdminMapLayer.density);
    final showZones = showUnanswered || showDensity;
    final visibleZones = [
      for (final z in zones)
        if ((showUnanswered && z.jobsUnanswered > 0) ||
            (showDensity && z.hasDemand))
          z,
    ];
    final visiblePartners = layers.contains(AdminMapLayer.partners)
        ? [
            for (final p in partners)
              if (p.hasLocation) p,
          ]
        : const <AdminPartner>[];
    final toReinforce = showZones
        ? adminZonesToReinforce(zones)
        : const <AdminMapZone>[];
    final summary = [
      adminMapSummary(points),
      if (showZones && zones.isNotEmpty) adminZonesSummary(zones),
      if (visiblePartners.isNotEmpty)
        '${visiblePartners.length} '
            '${visiblePartners.length == 1 ? 'parceiro' : 'parceiros'}',
      ?extrasNote,
    ].join('\n');
    final fitPoints = [
      for (final p in visible) LatLng(p.lat, p.lng),
      for (final p in visiblePartners) LatLng(p.lat!, p.lng!),
    ];

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
                  mapController: mapController,
                  options: MapOptions(
                    initialCenter: _portugal,
                    initialZoom: 6.5,
                    initialCameraFit: fitPoints.length > 1
                        ? CameraFit.coordinates(
                            coordinates: fitPoints,
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
                    if (visibleZones.isNotEmpty)
                      PolygonLayer(
                        polygons: [
                          for (final z in visibleZones)
                            adminZonePolygon(
                              z,
                              unanswered: showUnanswered,
                              density: showDensity,
                              selected: selectedZone?.cell == z.cell,
                            ),
                        ],
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
                    if (visibleZones.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          for (final z in visibleZones)
                            Marker(
                              point: LatLng(z.centerLat, z.centerLng),
                              width: AppSizes.minTapTarget,
                              height: AppSizes.minTapTarget,
                              child: _ZoneLabel(
                                zone: z,
                                unanswered: showUnanswered,
                                selected: selectedZone?.cell == z.cell,
                                onTap: () => onSelectZone?.call(z),
                              ),
                            ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        for (final p in visiblePartners)
                          Marker(
                            point: LatLng(p.lat!, p.lng!),
                            width: AppSizes.minTapTarget,
                            height: AppSizes.minTapTarget,
                            child: Semantics(
                              button: true,
                              label: 'Parceiro ${p.name}',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => onSelectPartner?.call(p),
                                child: Center(
                                  child: AdminPartnerMarker(
                                    status: p.status,
                                    kind: p.kind,
                                    selected: selectedPartner?.id == p.id,
                                  ),
                                ),
                              ),
                            ),
                          ),
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
            child: switch ((selected, selectedZone, selectedPartner)) {
              (final AdminMapPoint p, _, _) => Padding(
                key: ValueKey(p.id),
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: AdminMapPointCard(
                  point: p,
                  onOpen: () => onOpen(p),
                  onClose: () => onSelect(null),
                ),
              ),
              (_, final AdminMapZone z, _) => Padding(
                key: ValueKey('zone-${z.cell}'),
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: AdminMapZoneCard(zone: z, onClose: () => onSelect(null)),
              ),
              (_, _, final AdminPartner p) => Padding(
                key: ValueKey('partner-${p.id}'),
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: AdminMapPartnerCard(
                  partner: p,
                  onOpen: onOpenPartners,
                  onClose: () => onSelect(null),
                ),
              ),
              _ when toReinforce.isNotEmpty => Padding(
                key: const ValueKey('reinforce'),
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: AdminZonesToReinforce(
                  zones: toReinforce,
                  onTap: (z) => (onFocusZone ?? onSelectZone)?.call(z),
                ),
              ),
              _ => const SizedBox.shrink(),
            },
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

/// Quadrado de uma zona. Sem resposta: vermelho mais forte quanto maior a
/// parte dos pedidos sem resposta. Densidade: vermelho (ninguém cobre),
/// âmbar (1 ou 2), verde (3 ou mais).
Polygon adminZonePolygon(
  AdminMapZone z, {
  required bool unanswered,
  required bool density,
  bool selected = false,
}) {
  final useUnanswered = unanswered && z.jobsUnanswered > 0;
  final color = useUnanswered
      ? AppStatusColor.cancelled.foreground
      : adminZoneCoverageTone(z).foreground;
  final alpha = useUnanswered ? 0.15 + 0.35 * z.unansweredRate : 0.18;
  return Polygon(
    points: [
      LatLng(z.latMin, z.lngMin),
      LatLng(z.latMin, z.lngMax),
      LatLng(z.latMax, z.lngMax),
      LatLng(z.latMax, z.lngMin),
    ],
    color: color.withValues(alpha: alpha),
    borderColor: selected
        ? AppColors.textPrimary
        : color.withValues(alpha: 0.6),
    borderStrokeWidth: selected ? 2 : 1,
  );
}

/// Número no meio do quadrado: pedidos sem resposta (camada "Sem
/// resposta") ou jardineiros que cobrem (camada "Densidade").
class _ZoneLabel extends StatelessWidget {
  const _ZoneLabel({
    required this.zone,
    required this.unanswered,
    required this.selected,
    required this.onTap,
  });

  final AdminMapZone zone;
  final bool unanswered;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final z = zone;
    final showUnanswered = unanswered && z.jobsUnanswered > 0;
    final tone = showUnanswered
        ? AppStatusColor.cancelled
        : adminZoneCoverageTone(z);
    final value = showUnanswered ? z.jobsUnanswered : z.workersCovering;
    return Semantics(
      button: true,
      label: showUnanswered
          ? 'Zona ${z.area ?? ''}: $value pedidos sem resposta'
          : 'Zona ${z.area ?? ''}: $value jardineiros cobrem',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Container(
            width: AppSizes.adminZoneLabel,
            height: AppSizes.adminZoneLabel,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.background,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(
                color: selected ? AppColors.textPrimary : tone.foreground,
                width: AppSizes.adminMapDotBorder,
              ),
            ),
            child: Text(
              '$value',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: tone.foreground),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Angra · 3 pedidos, 2 sem resposta · 1 jardineiro cobre".
String adminZoneDetails(AdminMapZone z) {
  final hours = z.medianHoursFirstProposal;
  return [
    '${z.jobs} ${z.jobs == 1 ? 'pedido' : 'pedidos'} em $adminZoneDays dias'
        '${z.jobsUnanswered > 0 ? ', ${z.jobsUnanswered} sem resposta' : ''}'
        '${z.jobsCompleted > 0 ? ', ${z.jobsCompleted} concluídos' : ''}',
    if (hours != null) '1.ª proposta em ${adminHoursLabel(hours)} (mediana)',
    switch (z.workersCovering) {
      0 => 'nenhum jardineiro cobre',
      1 => '1 jardineiro cobre',
      final n => '$n jardineiros cobrem',
    },
    if (z.workersBased > 0) '${z.workersBased} com base aqui',
    if (z.partners > 0)
      '${z.partners} ${z.partners == 1 ? 'parceiro' : 'parceiros'}',
  ].join(' · ');
}

class AdminMapZoneCard extends StatelessWidget {
  const AdminMapZoneCard({
    required this.zone,
    required this.onClose,
    super.key,
  });

  final AdminMapZone zone;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final z = zone;
    return AdminPanelCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zona · ${z.area ?? 'sem nome'} ($adminZoneCellKm km)',
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  adminZoneDetails(z),
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
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

class AdminMapPartnerCard extends StatelessWidget {
  const AdminMapPartnerCard({
    required this.partner,
    required this.onClose,
    this.onOpen,
    super.key,
  });

  final AdminPartner partner;
  final VoidCallback? onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = partner;
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
                      p.name,
                      style: textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    AppStatusBadge(
                      label: p.status.label,
                      statusColor: p.status.tone,
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  [
                    ?p.brand,
                    ?p.locality,
                    adminPartnerReachLabel(p),
                  ].join(' · '),
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onOpen != null)
            TextButton(onPressed: onOpen, child: const Text('Parceiros')),
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

/// As zonas onde mais falta resposta, para tocar e ir lá no mapa.
class AdminZonesToReinforce extends StatelessWidget {
  const AdminZonesToReinforce({
    required this.zones,
    required this.onTap,
    super.key,
  });

  final List<AdminMapZone> zones;
  final ValueChanged<AdminMapZone> onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AdminPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zonas a reforçar',
            style: textTheme.titleSmall?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final z in zones)
                ActionChip(
                  avatar: Icon(
                    Icons.place_outlined,
                    size: AppSizes.inlineIcon,
                    color: z.jobsUnanswered > 0
                        ? AppStatusColor.cancelled.foreground
                        : adminZoneCoverageTone(z).foreground,
                  ),
                  label: Text(adminZoneChipLabel(z)),
                  onPressed: () => onTap(z),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Angra · 2 sem resposta" ou "Ponta · ninguém cobre" ou "Braga · 1 a cobrir".
String adminZoneChipLabel(AdminMapZone z) {
  final name = z.area ?? 'Zona sem nome';
  if (z.jobsUnanswered > 0) return '$name · ${z.jobsUnanswered} sem resposta';
  if (z.workersCovering == 0) return '$name · ninguém cobre';
  return '$name · ${z.workersCovering} a cobrir';
}
