import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../data/partner_model.dart';
import 'partner_banner_card.dart';

/// Corpo do ecrã de um parceiro. Só mostra as partes que o parceiro tem
/// preenchidas no painel ([partnerSections]): sem QR não há espaço para o
/// QR, sem link não há botão, e assim por diante.
///
/// Sem providers: o ecrã da app e a pré-visualização do painel usam o
/// mesmo widget.
class PartnerDetailView extends StatelessWidget {
  const PartnerDetailView({
    required this.partner,
    this.onCopyCode,
    this.onOpenLink,
    this.onOpenMap,
    this.onUnlock,
    this.showMapTiles = true,
    this.bannerImage,
    super.key,
  });

  final Partner partner;

  /// Foto ainda por gravar (pré-visualização do painel).
  final ImageProvider? bannerImage;
  final ValueChanged<String>? onCopyCode;
  final ValueChanged<String>? onOpenLink;
  final void Function(double lat, double lng)? onOpenMap;

  /// "Ver planos" no aviso do Pro+.
  final VoidCallback? onUnlock;

  /// `false` nos testes (sem rede).
  final bool showMapTiles;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = partner;
    final sections = partnerSections(p);
    final subtitle = {?p.brand, p.kind.label}.join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppStaggeredEntrance(
          index: 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: PartnerBanner(
              partner: p,
              image: bannerImage,
              height: AppSizes.partnerDetailBannerHeight,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppStaggeredEntrance(
          index: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      style: textTheme.headlineSmall?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (p.locked) const PartnerProPlusTag(),
                ],
              ),
              Text(
                subtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (p.headline != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  p.headline!,
                  style: textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final (i, section) in sections.indexed) ...[
          const SizedBox(height: AppSpacing.md),
          AppStaggeredEntrance(
            index: i + 2 < 6 ? i + 2 : 6,
            child: KeyedSubtree(
              key: ValueKey('partner-section-${section.name}'),
              child: _section(context, section),
            ),
          ),
        ],
      ],
    );
  }

  Widget _section(BuildContext context, PartnerSection section) {
    final textTheme = Theme.of(context).textTheme;
    final body = textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary);
    final p = partner;
    switch (section) {
      case PartnerSection.description:
        return _Card(child: Text(p.description!, style: body));
      case PartnerSection.locked:
        return _LockedCard(perks: p.lockedPerks, onUnlock: onUnlock);
      case PartnerSection.discountCode:
        final code = p.discountCode!;
        return _Card(
          title: 'Código de desconto',
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    border: Border.all(color: AppColors.agendaAppBorder),
                  ),
                  child: SelectableText(
                    code,
                    style: textTheme.titleLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              TextButton.icon(
                onPressed: onCopyCode == null ? null : () => onCopyCode!(code),
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copiar'),
              ),
            ],
          ),
        );
      case PartnerSection.barcode:
        return _Card(
          title: 'Código de barras',
          hint: 'Mostra no balcão para lerem.',
          child: Center(
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.partnerBarcodeMaxWidth,
              ),
              padding: const EdgeInsets.all(AppSpacing.sm),
              color: AppColors.surface,
              child: BarcodeWidget(
                barcode: p.barcodeFormat == PartnerBarcodeFormat.ean13
                    ? Barcode.ean13()
                    : Barcode.code128(),
                data: p.barcodeValue!,
                height: AppSizes.partnerBarcodeHeight,
                color: AppColors.textPrimary,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                ),
                errorBuilder: (_, _) => Text(p.barcodeValue!, style: body),
              ),
            ),
          ),
        );
      case PartnerSection.qr:
        return _Card(
          title: 'QR da promoção',
          hint: 'Mostra no balcão para lerem.',
          child: Center(
            child: QrImageView(
              data: p.qrValue!,
              size: AppSizes.partnerQr,
              backgroundColor: AppColors.surface,
              semanticsLabel: 'QR da promoção de ${p.name}',
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.textPrimary,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        );
      case PartnerSection.location:
        return _LocationCard(
          partner: p,
          showTiles: showMapTiles,
          onOpenMap: onOpenMap,
        );
      case PartnerSection.link:
        return SizedBox(
          height: AppSizes.buttonHeight,
          child: FilledButton.icon(
            onPressed: onOpenLink == null
                ? null
                : () => onOpenLink!(p.linkUrl!),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(p.linkLabel ?? 'Abrir o site'),
          ),
        );
      case PartnerSection.terms:
        final until = p.validUntil;
        return _Card(
          title: 'Condições',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.terms != null) Text(p.terms!, style: body),
              if (until != null) ...[
                if (p.terms != null) const SizedBox(height: AppSpacing.xs),
                Text(
                  'Válido até ${DateFormat('dd/MM/yyyy').format(until)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        );
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.title, this.hint});

  final String? title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: textTheme.titleSmall?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// O parceiro é só Pro+ e quem vê não é: diz o que fica disponível.
class _LockedCard extends StatelessWidget {
  const _LockedCard({required this.perks, this.onUnlock});

  final List<String> perks;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final list = switch (perks.length) {
      1 => perks.first,
      _ => '${perks.sublist(0, perks.length - 1).join(', ')} e ${perks.last}',
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.logoAccent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppColors.logoAccent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Disponível no Pro+',
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Com o Pro+ vês aqui o $list deste parceiro.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (onUnlock != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  OutlinedButton(
                    onPressed: onUnlock,
                    child: const Text('Ver planos'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.partner,
    required this.showTiles,
    this.onOpenMap,
  });

  final Partner partner;
  final bool showTiles;
  final void Function(double lat, double lng)? onOpenMap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = partner;
    final address = {?p.address, ?p.locality}.join(', ');
    final point = p.hasLocation ? LatLng(p.lat!, p.lng!) : null;
    return _Card(
      title: 'Onde fica',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (point != null) ...[
            SizedBox(
              height: AppSizes.partnerMapHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.input),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                    onTap: onOpenMap == null
                        ? null
                        : (_, _) => onOpenMap!(point.latitude, point.longitude),
                  ),
                  children: [
                    if (showTiles)
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'pt.projardim.app',
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: AppSizes.mapPin,
                          height: AppSizes.mapPin,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.location_on_rounded,
                            size: AppSizes.mapPin,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (address.isNotEmpty)
            Text(
              address,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          if (point != null && onOpenMap != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onOpenMap!(point.latitude, point.longitude),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Abrir no mapa'),
              ),
            ),
        ],
      ),
    );
  }
}
