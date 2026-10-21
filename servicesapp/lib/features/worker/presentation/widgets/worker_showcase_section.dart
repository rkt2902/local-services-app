import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/worker_showcase.dart';
import '../../../../core/widgets/app_toast.dart';

/// Apresentação, destaques e links que o worker escolheu mostrar (0051).
/// Usado no perfil que o cliente abre a partir das propostas (folha de
/// avaliações) e no cartão público `/w/:workerId`. Não mostra nada se o
/// worker não preencheu nada.
///
/// Design U6: "Sobre" e "Em destaque" em cartões brancos com o título em
/// maiúsculas, links em duas colunas e a nota de que é informação do
/// próprio jardineiro.
class WorkerShowcaseSection extends StatelessWidget {
  const WorkerShowcaseSection({
    super.key,
    required this.highlights,
    required this.socialLinks,
    this.bio,
  });

  final String? bio;
  final List<String> highlights;
  final List<WorkerSocialLink> socialLinks;

  bool get isEmpty =>
      (bio == null || bio!.trim().isEmpty) &&
      highlights.isEmpty &&
      socialLinks.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final hasBio = bio != null && bio!.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasBio)
          _ShowcaseCard(
            title: 'SOBRE',
            child: Text(
              bio!.trim(),
              style:
                  textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        if (highlights.isNotEmpty) ...[
          if (hasBio) const SizedBox(height: AppSpacing.sm),
          _ShowcaseCard(
            title: 'EM DESTAQUE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < highlights.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      top: i == 0 ? 0 : AppSpacing.s10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: AppSizes.inlineIcon,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            highlights[i],
                            style: textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (socialLinks.isNotEmpty) ...[
          if (hasBio || highlights.isNotEmpty)
            const SizedBox(height: AppSpacing.md),
          Text(
            'VER TRABALHOS E REDES',
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (context, constraints) {
              // Duas colunas, como no design; um link sozinho fica a meio.
              final width = (constraints.maxWidth - AppSpacing.xs) / 2;
              return Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final link in socialLinks)
                    SizedBox(
                      width: width,
                      child: _SocialLinkButton(link: link),
                    ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Informação partilhada pelo jardineiro.',
          style: textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ShowcaseCard extends StatelessWidget {
  const _ShowcaseCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

class _SocialLinkButton extends StatelessWidget {
  const _SocialLinkButton({required this.link});

  final WorkerSocialLink link;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(link.url);
    // Só https: o link vem de outra pessoa e abre fora da app.
    if (uri == null || uri.scheme != 'https') return;
    final toast = AppToast.maybeOf(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      toast?.error('Não foi possível abrir o link.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      link: true,
      label: 'Abrir ${link.label}',
      excludeSemantics: true,
      child: OutlinedButton(
        onPressed: () => _open(context),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSizes.linkButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              socialLinkIcon(link),
              size: AppSizes.inlineIcon,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                link.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ícone de cada tipo de link (o Material não tem o logótipo do Instagram).
IconData socialLinkIcon(WorkerSocialLink link) => switch (link.kind) {
      WorkerSocialLinkKind.instagram => Icons.camera_alt_outlined,
      WorkerSocialLinkKind.facebook => Icons.facebook_rounded,
      WorkerSocialLinkKind.website => Icons.language_rounded,
      WorkerSocialLinkKind.other => switch (link.label) {
          'TikTok' => Icons.tiktok_rounded,
          'YouTube' => Icons.smart_display_outlined,
          'Google Maps' => Icons.map_outlined,
          _ => Icons.link_rounded,
        },
    };
