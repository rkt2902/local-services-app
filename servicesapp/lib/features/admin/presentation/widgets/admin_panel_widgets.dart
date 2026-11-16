import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/error_utils.dart';
import '../../../../core/utils/phone_utils.dart';
import '../../../../core/widgets/app_motion.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/app_whatsapp_button.dart';
import '../../application/admin_providers.dart';

/// Largura a partir da qual a lista e a ficha ficam lado a lado. Abaixo
/// disto a ficha abre por cima da lista (como pede a estrutura do painel).
const double adminSplitMinWidth = 1024;

/// Largura da coluna da lista no modo lado a lado.
const double adminListColumnWidth = 420;

/// Lista à esquerda e ficha à direita em ecrãs largos; num ecrã estreito
/// mostra só a ficha quando há uma escolhida. A ficha troca com
/// fade-through quando muda de alvo.
class AdminSplitView extends StatelessWidget {
  const AdminSplitView({
    required this.list,
    required this.detailBuilder,
    required this.detailKey,
    required this.emptyDetail,
    super.key,
  });

  final Widget list;

  /// `null` = nada escolhido. Recebe `overlay = true` quando a ficha está
  /// por cima da lista (ecrã estreito) e precisa de botão para voltar.
  final Widget Function(bool overlay)? detailBuilder;
  final Object? detailKey;
  final Widget emptyDetail;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= adminSplitMinWidth;
        if (!wide) {
          return AppFadeThroughSwitcher(
            switchKey: detailKey ?? 'list',
            child: detailBuilder?.call(true) ?? list,
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: adminListColumnWidth, child: list),
            const VerticalDivider(width: 1, color: AppColors.divider),
            Expanded(
              child: AppFadeThroughSwitcher(
                switchKey: detailKey ?? 'empty',
                child: detailBuilder?.call(false) ?? emptyDetail,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Largura da barra lateral do painel.
const double adminSidebarWidth = 220;

/// Cartão branco com borda, como os da ficha do jardineiro.
class AdminPanelCard extends StatelessWidget {
  const AdminPanelCard({required this.child, this.title, super.key});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
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

/// Linha "rótulo: valor" dentro de um cartão.
class AdminInfoRow extends StatelessWidget {
  const AdminInfoRow({
    required this.label,
    required this.value,
    this.trailing,
    super.key,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Botão de copiar um texto (id curto, email).
class AdminCopyButton extends StatelessWidget {
  const AdminCopyButton({
    required this.value,
    this.tooltip = 'Copiar',
    super.key,
  });

  final String value;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: const Icon(
        Icons.copy_rounded,
        size: 18,
        color: AppColors.textSecondary,
      ),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) AppToast.of(context).show('Copiado.');
      },
    );
  }
}

/// "Mostrar contacto": o telefone só aparece depois do clique, e a
/// consulta fica registada em admin_actions pela RPC.
class AdminRevealPhone extends ConsumerStatefulWidget {
  const AdminRevealPhone({
    required this.personId,
    required this.maskedPhone,
    super.key,
  });

  final String personId;
  final String? maskedPhone;

  @override
  ConsumerState<AdminRevealPhone> createState() => _AdminRevealPhoneState();
}

class _AdminRevealPhoneState extends ConsumerState<AdminRevealPhone> {
  String? _phone;
  bool _loading = false;

  Future<void> _reveal() async {
    setState(() => _loading = true);
    try {
      final phone = await ref
          .read(adminRepositoryProvider)
          .revealPhone(widget.personId);
      if (!mounted) return;
      setState(() => _phone = phone);
      if (phone == null) AppToast.of(context).show('Sem telefone.');
    } catch (e) {
      if (mounted) AppToast.of(context).show(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (widget.maskedPhone == null) {
      return Text(
        'Sem telefone',
        style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    }
    final phone = _phone;
    return AppFadeThroughSwitcher(
      switchKey: phone ?? 'masked',
      child: phone == null
          ? Wrap(
              spacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  widget.maskedPhone!,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                TextButton.icon(
                  onPressed: _loading ? null : _reveal,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Mostrar contacto'),
                ),
              ],
            )
          : Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SelectableText(
                  phone,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                AdminCopyButton(value: phone),
                AppWhatsAppButton(
                  compact: true,
                  onPressed: () => openWhatsAppOrWarn(context, phone),
                ),
              ],
            ),
    );
  }
}

/// Paginação "Anteriores · 1 de 3 · Seguintes".
class AdminPager extends StatelessWidget {
  const AdminPager({
    required this.page,
    required this.pages,
    required this.onPage,
    super.key,
  });

  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (pages <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: page == 0 ? null : () => onPage(page - 1),
          icon: const Icon(Icons.chevron_left_rounded),
          label: const Text('Anteriores'),
        ),
        Text('${page + 1} de $pages'),
        TextButton.icon(
          onPressed: page >= pages - 1 ? null : () => onPage(page + 1),
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('Seguintes'),
        ),
      ],
    );
  }
}

/// Linha de uma lista do painel, com destaque quando está aberta à direita.
class AdminListTileCard extends StatelessWidget {
  const AdminListTileCard({
    required this.child,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final Widget child;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primaryTint : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
