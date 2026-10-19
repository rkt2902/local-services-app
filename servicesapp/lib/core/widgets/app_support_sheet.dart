import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_links.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_sizes.dart';
import '../theme/app_spacing.dart';
import 'app_motion.dart';
import 'app_sheet.dart';

/// "Contacto e suporte" (design U7): email de suporte da ProJardim com
/// "Copiar email" e "Escrever". "Escrever" abre a app de email do telemóvel
/// (`mailto:`), fora da ProJardim: é o canal de suporte da app, não contacto
/// entre cliente e jardineiro (esse é só por WhatsApp). Partilhado pela
/// conta do cliente e pela do jardineiro.
Future<void> showSupportContactSheet(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  return AppSheet.show<void>(
    context,
    builder: (sheetCtx) => AppSupportSheet(
      email: AppLinks.supportEmail,
      responseTimeLabel: AppLinks.supportResponseTime,
      onClose: () => Navigator.pop(sheetCtx),
      onCopyEmail: () async {
        await Clipboard.setData(
          const ClipboardData(text: AppLinks.supportEmail),
        );
        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
        messenger.showSnackBar(
          const SnackBar(content: Text('Email copiado.')),
        );
      },
      onComposeEmail: () async {
        var opened = false;
        try {
          opened = await launchUrl(supportMailtoUri(AppLinks.supportEmail));
        } catch (_) {
          opened = false;
        }
        if (opened) {
          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
          return;
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Não encontrámos uma app de email. Copia o endereço e '
              'escreve-nos.',
            ),
          ),
        );
      },
    ),
  );
}

/// `mailto:` com o assunto já escrito. Espaços como `%20`: alguns clientes
/// de email mostram o `+` de `queryParameters` à letra.
@visibleForTesting
Uri supportMailtoUri(String email) => Uri.parse(
      'mailto:$email?subject=${Uri.encodeComponent('Ajuda ProJardim')}',
    );

class AppSupportSheet extends StatelessWidget {
  const AppSupportSheet({
    super.key,
    required this.email,
    required this.responseTimeLabel,
    required this.onClose,
    required this.onCopyEmail,
    required this.onComposeEmail,
  });

  final String email;
  final String responseTimeLabel;
  final VoidCallback onClose;
  final VoidCallback onCopyEmail;
  final VoidCallback onComposeEmail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
    );
    final buttonText = textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: AppSizes.sheetHandleWidth,
                height: AppSizes.sheetHandleHeight,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: 0,
              child: Row(
                children: [
                  Container(
                    width: AppSizes.dialogIconBox,
                    height: AppSizes.dialogIconBox,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                    child: const Icon(
                      Icons.support_agent_outlined,
                      color: AppColors.primary,
                      size: AppSizes.dialogIcon,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contacto e suporte',
                          style: textTheme.titleLarge?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          responseTimeLabel,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    tooltip: 'Fechar',
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.mail_outline_rounded,
                      size: AppSizes.inlineIcon,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: SelectableText(
                        email,
                        maxLines: 1,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppStaggeredEntrance(
              index: 2,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCopyEmail,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          AppSizes.compactButtonHeight,
                        ),
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.divider),
                        shape: buttonShape,
                        textStyle: buttonText,
                      ),
                      icon: const Icon(
                        Icons.copy_rounded,
                        size: AppSizes.inlineIcon,
                      ),
                      label: const Text('Copiar email'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onComposeEmail,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          AppSizes.compactButtonHeight,
                        ),
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.surface,
                        shape: buttonShape,
                        textStyle: buttonText,
                      ),
                      icon: const Icon(
                        Icons.send_rounded,
                        size: AppSizes.inlineIcon,
                      ),
                      label: const Text('Escrever'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
