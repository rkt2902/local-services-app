import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_links.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_sheet.dart';

/// "Contacto & suporte": email de suporte selecionável e com botão de
/// copiar. Sem `mailto:` de propósito: o contacto dentro da app é só por
/// WhatsApp; o email abre-se fora, à mão. Partilhado pela conta do cliente
/// e pela do jardineiro.
Future<void> showSupportContactSheet(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  return AppSheet.show<void>(
    context,
    builder: (sheetCtx) => AppSheet(
      title: 'Contacto & suporte',
      onClose: () => Navigator.pop(sheetCtx),
      primaryActionLabel: 'Copiar email',
      primaryActionIcon: Icons.copy_rounded,
      onPrimaryAction: () async {
        await Clipboard.setData(
          const ClipboardData(text: AppLinks.supportEmail),
        );
        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
        messenger.showSnackBar(
          const SnackBar(content: Text('Email copiado.')),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Precisas de ajuda? Escreve-nos para este email e '
            'respondemos o mais depressa possível.',
            style: Theme.of(sheetCtx).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            AppLinks.supportEmail,
            style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                  color: AppColors.primary,
                ),
          ),
        ],
      ),
    ),
  );
}
