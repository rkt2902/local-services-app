import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_links.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// "Contacto & suporte": email de suporte selecionável e com botão de
/// copiar. Sem `mailto:` de propósito: o contacto dentro da app é só por
/// WhatsApp; o email abre-se fora, à mão. Partilhado pela conta do cliente
/// e pela do jardineiro.
Future<void> showSupportContactSheet(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contacto & suporte',
              style: Theme.of(sheetCtx).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Precisas de ajuda? Escreve-nos para este email e '
              'respondemos o mais depressa possível.',
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              AppLinks.supportEmail,
              style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: AppLinks.supportEmail),
                );
                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Email copiado.')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copiar email'),
            ),
          ],
        ),
      ),
    ),
  );
}
