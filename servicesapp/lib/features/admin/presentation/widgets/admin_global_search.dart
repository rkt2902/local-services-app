import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../application/admin_providers.dart';
import '../../data/admin_support_models.dart';

/// Pesquisa global, sempre no topo do painel. Aceita email, telefone,
/// nome, id ou o início de um id (8 carateres dos emails de suporte).
/// Enter com um só resultado abre logo a ficha.
class AdminGlobalSearch extends ConsumerStatefulWidget {
  const AdminGlobalSearch({super.key});

  @override
  ConsumerState<AdminGlobalSearch> createState() => _AdminGlobalSearchState();
}

class _AdminGlobalSearchState extends ConsumerState<AdminGlobalSearch> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Cada pesquisa fica registada: espera que a pessoa pare de escrever.
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
  }

  void _open(AdminSearchHit hit) {
    _clear();
    FocusScope.of(context).unfocus();
    context.go(hit.route);
  }

  Future<void> _onSubmitted(String value) async {
    _debounce?.cancel();
    final q = value.trim();
    setState(() => _query = q);
    if (q.length < 2) return;
    final hits = await ref.read(adminSearchProvider(q).future);
    if (mounted && hits.length == 1) _open(hits.first);
  }

  @override
  Widget build(BuildContext context) {
    // Os resultados ficam até abrir um ou limpar a pesquisa.
    final showResults = _query.length >= 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSearchField(
          controller: _controller,
          hintText: 'Email, telefone, nome ou id (#4f8f1350)',
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
          onClear: _clear,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: showResults
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: _SearchResults(query: _query, onOpen: _open),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query, required this.onOpen});

  final String query;
  final ValueChanged<AdminSearchHit> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final hitsAsync = ref.watch(adminSearchProvider(query));
    Widget message(String text) => Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(
        text,
        style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      ),
    );
    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: hitsAsync.when(
        loading: () => message('A procurar…'),
        error: (e, _) => message(friendlyError(e)),
        data: (hits) {
          if (hits.isEmpty) return message('Nada encontrado para "$query".');
          return ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            itemCount: hits.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.divider),
            itemBuilder: (context, i) {
              final hit = hits[i];
              return AppStaggeredEntrance(
                index: i < 6 ? i : 6,
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    adminSearchKindIcon(hit.kind),
                    color: AppColors.primary,
                  ),
                  title: Text(
                    hit.title,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    hit.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  onTap: () => onOpen(hit),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

IconData adminSearchKindIcon(AdminSearchKind kind) => switch (kind) {
  AdminSearchKind.job => Icons.assignment_outlined,
  AdminSearchKind.client => Icons.person_outline_rounded,
  AdminSearchKind.worker => Icons.yard_outlined,
};
