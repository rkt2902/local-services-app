import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/worker_showcase.dart';

/// Apresentação, destaques e links que o worker escolheu mostrar (0051).
/// Usado no perfil que o cliente abre a partir das propostas (folha de
/// avaliações) e no cartão público `/w/:workerId`. Não mostra nada se o
/// worker não preencheu nada.
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasBio) ...[
          Text(
            'Sobre',
            style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            bio!.trim(),
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
        ],
        if (highlights.isNotEmpty) ...[
          if (hasBio) const SizedBox(height: AppSpacing.md),
          Text(
            'Em destaque',
            style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final highlight in highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      highlight,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (socialLinks.isNotEmpty) ...[
          SizedBox(
            height: highlights.isNotEmpty
                ? AppSpacing.xs
                : (hasBio ? AppSpacing.md : 0),
          ),
          Text(
            'Ver trabalhos e redes',
            style: textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final link in socialLinks) _SocialLinkButton(link: link),
            ],
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

class _SocialLinkButton extends StatelessWidget {
  const _SocialLinkButton({required this.link});

  final WorkerSocialLink link;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(link.url);
    // Só https: o link vem de outra pessoa e abre fora da app.
    if (uri == null || uri.scheme != 'https') return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      link: true,
      label: 'Abrir ${link.label}',
      excludeSemantics: true,
      child: Material(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(socialLinkIcon(link), size: 18, color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  link.label,
                  style: textTheme.labelLarge?.copyWith(color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
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
