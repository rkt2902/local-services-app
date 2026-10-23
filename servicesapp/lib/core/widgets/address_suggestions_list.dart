import 'package:flutter/material.dart';

import '../services/geocoding_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import 'app_motion.dart';

/// Quando a pesquisa não encontra a morada: o mapa resolve sempre.
const addressNotFoundHint =
    'Não encontrámos esta morada. Toca no mapa no sítio exato; a morada '
    'podes escrevê-la à mão.';

/// Lista de sugestões por baixo de um campo de morada: a carregar, sem
/// resultados (com [emptyHint]) ou as moradas encontradas. Só apresentação:
/// quem a usa faz a pesquisa e decide o que acontece ao escolher.
class AddressSuggestionsList extends StatelessWidget {
  const AddressSuggestionsList({
    super.key,
    required this.suggestions,
    required this.loading,
    required this.onSelected,
    this.emptyHint,
  });

  final List<AddressSuggestion> suggestions;
  final bool loading;
  final ValueChanged<AddressSuggestion> onSelected;

  /// Texto quando a pesquisa acabou sem nada; `null` não mostra nada.
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (!loading && suggestions.isEmpty && emptyHint == null) {
      return const SizedBox.shrink();
    }

    final Widget child;
    if (loading && suggestions.isEmpty) {
      child = Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            const SizedBox.square(
              dimension: AppSizes.inlineSpinner,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'A procurar moradas...',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    } else if (suggestions.isEmpty) {
      child = Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          emptyHint!,
          style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      );
    } else {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < suggestions.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            InkWell(
              onTap: () => onSelected(suggestions[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: AppSizes.inlineIcon,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            suggestions[i].title,
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (suggestions[i].subtitle.isNotEmpty)
                            Text(
                              suggestions[i].subtitle,
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    }

    return AppStaggeredEntrance(
      index: 0,
      child: Container(
        margin: const EdgeInsets.only(top: AppSpacing.xxs),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(color: AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
