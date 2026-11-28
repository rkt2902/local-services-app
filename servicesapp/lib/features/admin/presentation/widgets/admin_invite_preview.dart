import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/admin_invite_templates.dart';

/// Pré-visualização do convite no painel, feita dos mesmos blocos que o
/// HTML enviado ([AdminInviteMessage]). Não é o HTML em si: os programas
/// de email mudam um pouco o aspeto, mas o texto é exatamente o mesmo.
class AdminInvitePreview extends StatelessWidget {
  const AdminInvitePreview({required this.message, super.key});

  final AdminInviteMessage message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final m = message;
    final body = textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary);
    final small = textTheme.bodySmall?.copyWith(color: AppColors.textSecondary);

    Widget paragraph(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text, style: body),
    );

    final footer = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in m.designed ? m.footerLines : m.footerLines.skip(1))
          Text(line, style: small),
        Text(
          AdminInviteMessage.optoutLabel,
          style: small?.copyWith(decoration: TextDecoration.underline),
        ),
      ],
    );

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          paragraph(m.greeting),
          for (final p in m.paragraphs) paragraph(p),
          if (m.benefits.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (m.benefitsTitle != null)
                    Text(
                      m.benefitsTitle!.toUpperCase(),
                      style: textTheme.labelMedium?.copyWith(
                        color: AppColors.primaryPressed,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  for (final b in m.benefits)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '✓',
                            style: body?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(child: Text(b, style: body)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (m.founderTitle != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.founderSurface,
                border: Border.all(color: AppColors.founderBorder),
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.founderTitle!,
                    style: textTheme.titleSmall?.copyWith(
                      color: AppColors.founderTitle,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    m.founderBody ?? '',
                    style: body?.copyWith(color: AppColors.founderText),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (m.ctaLabel != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Text(
                  m.ctaLabel!,
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.surface,
                  ),
                ),
              ),
            ),
            if (m.ctaHint != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Text(
                  m.ctaHint!,
                  textAlign: TextAlign.center,
                  style: small,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          for (final p in m.closingParagraphs) paragraph(p),
          Text(m.signOff, style: body),
          Text(
            m.signedBy,
            style: body?.copyWith(
              fontWeight: m.designed ? FontWeight.w700 : null,
            ),
          ),
          for (final line in m.signatureLines)
            Text(line, style: m.designed ? small : body),
          const SizedBox(height: AppSpacing.md),
          if (m.designed) ...[
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: AppSpacing.md),
          ],
          footer,
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho como no programa de email: assunto.
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Assunto: ', style: small),
                  TextSpan(
                    text: m.subject.isEmpty ? '(sem assunto)' : m.subject,
                    style: textTheme.titleSmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (m.designed)
            Container(
              color: AppColors.primary,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ProJardim',
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.surface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (m.kicker != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      m.kicker!.toUpperCase(),
                      style: textTheme.labelSmall?.copyWith(
                        color: AppColors.onPrimaryMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (m.heading != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      m.heading!,
                      style: textTheme.headlineSmall?.copyWith(
                        color: AppColors.surface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          content,
        ],
      ),
    );
  }
}
