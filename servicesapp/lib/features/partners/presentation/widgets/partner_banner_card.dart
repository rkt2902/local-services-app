import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/partner_model.dart';

/// Topo de um parceiro: a foto, ou (sem foto) uma faixa verde com o ícone
/// do tipo. Igual no cartão da lista e no ecrã do parceiro.
class PartnerBanner extends StatelessWidget {
  const PartnerBanner({
    required this.partner,
    this.height = AppSizes.partnerBannerHeight,
    this.image,
    super.key,
  });

  final Partner partner;
  final double height;

  /// Foto ainda por gravar (pré-visualização do painel). Sem isto usa a
  /// foto do parceiro.
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final url = partner.imageUrl;
    final image =
        this.image ??
        (url == null ? null : ResizeImage(NetworkImage(url), width: 1000));
    final fallback = ColoredBox(
      color: AppColors.primaryContainer,
      child: Center(
        child: Icon(
          partner.kind.icon,
          size: AppSizes.partnerBannerIcon,
          color: AppColors.primary,
        ),
      ),
    );
    return SizedBox(
      height: height,
      width: double.infinity,
      child: image == null
          ? fallback
          : Image(
              image: image,
              fit: BoxFit.cover,
              semanticLabel: partner.name,
              errorBuilder: (_, _, _) => fallback,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : fallback,
            ),
    );
  }
}

/// Selo "Pro+" nos parceiros cujos códigos são só do Pro+.
class PartnerProPlusTag extends StatelessWidget {
  const PartnerProPlusTag({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: AppColors.surface,
      fontWeight: FontWeight.w700,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.logoAccent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: style?.fontSize, color: style?.color),
          const SizedBox(width: AppSpacing.xxs),
          Text('Pro+', style: style),
        ],
      ),
    );
  }
}

/// Cartão de um parceiro na lista: banner, nome e a frase curta. Toca para
/// abrir o ecrã do parceiro.
class PartnerBannerCard extends StatelessWidget {
  const PartnerBannerCard({
    required this.partner,
    required this.onTap,
    this.image,
    super.key,
  });

  final Partner partner;
  final VoidCallback onTap;

  /// Foto ainda por gravar (pré-visualização do painel).
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = partner;
    final subtitle = {?p.brand, p.kind.label}.join(' · ');
    return Semantics(
      button: true,
      label: [p.name, ?p.headline].join(', '),
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.divider),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  PartnerBanner(partner: p, image: image),
                  if (p.locked)
                    const Positioned(
                      top: AppSpacing.xs,
                      right: AppSpacing.xs,
                      child: PartnerProPlusTag(),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: textTheme.titleMedium?.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (p.headline != null) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              p.headline!,
                              style: textTheme.bodyMedium?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
