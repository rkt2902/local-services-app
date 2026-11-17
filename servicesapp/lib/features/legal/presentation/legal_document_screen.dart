import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion_tokens.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_back_button.dart';
import '../../../core/widgets/app_bar_title.dart';
import '../../../core/widgets/app_inline_error.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../core/widgets/app_screen_loading_skeleton.dart';
import '../../../core/widgets/app_toast.dart';
import '../application/legal_document_provider.dart';
import '../domain/legal_document.dart';

/// Termos de utilização ou Política de Privacidade dentro da app (rotas
/// `/termos` e `/privacidade`, públicas). O texto vem de `assets/legal/`,
/// por isso abre sem rede e é sempre a versão desta build.
class LegalDocumentScreen extends ConsumerWidget {
  const LegalDocumentScreen({super.key, required this.kind});

  final LegalDocumentKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(legalDocumentProvider(kind));
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        leading: const AppBackButton(fallbackLocation: '/'),
        titleSpacing: 0,
        title: AppBarTitle(title: kind.shortTitle),
      ),
      body: SafeArea(
        top: false,
        child: doc.when(
          data: (d) => LegalDocumentView(
            kind: kind,
            document: d,
            onOpenLink: (url) => _openLink(context, url),
            onOpenOther: () => context.pushReplacement(_other.route),
          ),
          loading: () => const AppScreenLoadingSkeleton(),
          error: (_, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: AppInlineError(
              message: 'Não foi possível abrir o texto. Tenta outra vez.',
              onRetry: () => ref.invalidate(legalDocumentProvider(kind)),
            ),
          ),
        ),
      ),
    );
  }

  LegalDocumentKind get _other => kind == LegalDocumentKind.terms
      ? LegalDocumentKind.privacy
      : LegalDocumentKind.terms;

  Future<void> _openLink(BuildContext context, String url) async {
    final toast = AppToast.maybeOf(context);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) toast?.error('Não foi possível abrir a ligação.');
  }
}

/// Vista pura (testável sem rede): cabeçalho, índice e secções em cartões.
class LegalDocumentView extends StatefulWidget {
  const LegalDocumentView({
    super.key,
    required this.kind,
    required this.document,
    required this.onOpenLink,
    required this.onOpenOther,
  });

  final LegalDocumentKind kind;
  final LegalDocument document;
  final ValueChanged<String> onOpenLink;
  final VoidCallback onOpenOther;

  @override
  State<LegalDocumentView> createState() => _LegalDocumentViewState();
}

class _LegalDocumentViewState extends State<LegalDocumentView> {
  late List<GlobalKey> _sectionKeys;

  @override
  void initState() {
    super.initState();
    _sectionKeys = _keysFor(widget.document);
  }

  @override
  void didUpdateWidget(LegalDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      _sectionKeys = _keysFor(widget.document);
    }
  }

  List<GlobalKey> _keysFor(LegalDocument d) => [
        for (var i = 0; i < d.sections.length; i++) GlobalKey(),
      ];

  void _scrollTo(int index) {
    final ctx = _sectionKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AppMotionDuration.screen,
      curve: AppMotionCurve.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.document;
    final otherLabel = widget.kind == LegalDocumentKind.terms
        ? 'Ler a Política de Privacidade'
        : 'Ler os Termos de utilização';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppStaggeredEntrance(
            index: 0,
            child: _LegalHero(
              kind: widget.kind,
              document: d,
              onOpenLink: widget.onOpenLink,
            ),
          ),
          if (d.sections.length > 3) ...[
            const SizedBox(height: AppSpacing.sm),
            AppStaggeredEntrance(
              index: 1,
              child: _LegalIndex(sections: d.sections, onTap: _scrollTo),
            ),
          ],
          for (var i = 0; i < d.sections.length; i++) ...[
            const SizedBox(height: AppSpacing.sm),
            AppStaggeredEntrance(
              index: i + 2,
              child: KeyedSubtree(
                key: _sectionKeys[i],
                child: _LegalSectionCard(
                  section: d.sections[i],
                  onOpenLink: widget.onOpenLink,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Center(
            child: TextButton.icon(
              onPressed: widget.onOpenOther,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size(0, AppSizes.minTapTarget),
              ),
              icon: const Icon(Icons.description_outlined),
              label: Text(otherLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalHero extends StatelessWidget {
  const _LegalHero({
    required this.kind,
    required this.document,
    required this.onOpenLink,
  });

  final LegalDocumentKind kind;
  final LegalDocument document;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final updated = document.updatedAt;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppSizes.dialogIconBox,
                height: AppSizes.dialogIconBox,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                ),
                child: Icon(
                  kind == LegalDocumentKind.terms
                      ? Icons.handshake_outlined
                      : Icons.shield_outlined,
                  color: AppColors.primary,
                  size: AppSizes.dialogIcon,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  document.title.isEmpty ? kind.shortTitle : document.title,
                  style: textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (updated != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                'Última atualização: $updated',
                style: textTheme.labelMedium?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          for (final block in document.intro) ...[
            const SizedBox(height: AppSpacing.sm),
            _LegalBlockView(block: block, onOpenLink: onOpenLink),
          ],
        ],
      ),
    );
  }
}

class _LegalIndex extends StatelessWidget {
  const _LegalIndex({required this.sections, required this.onTap});

  final List<LegalSection> sections;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.divider),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: AppColors.surface),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(),
          collapsedShape: const RoundedRectangleBorder(),
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.textSecondary,
          leading: const Icon(Icons.list_alt_rounded, color: AppColors.primary),
          title: Text(
            'Índice',
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            '${sections.length} secções',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          childrenPadding: const EdgeInsets.only(bottom: AppSpacing.xs),
          children: [
            for (var i = 0; i < sections.length; i++)
              InkWell(
                onTap: () => onTap(i),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSizes.minTapTarget,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            sections[i].title,
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "4. Para que usamos" -> ("4", "Para que usamos").
(String?, String) splitSectionTitle(String title) {
  final m = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(title);
  if (m == null) return (null, title);
  return (m.group(1), m.group(2)!);
}

class _LegalSectionCard extends StatelessWidget {
  const _LegalSectionCard({required this.section, required this.onOpenLink});

  final LegalSection section;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (number, title) = splitSectionTitle(section.title);
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (number != null) ...[
                Container(
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.s28,
                    minHeight: AppSpacing.s28,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    number,
                    style: textTheme.labelLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xxs / 2),
                  child: Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          for (final block in section.blocks) ...[
            const SizedBox(height: AppSpacing.sm),
            _LegalBlockView(block: block, onOpenLink: onOpenLink),
          ],
        ],
      ),
    );
  }
}

class _LegalBlockView extends StatelessWidget {
  const _LegalBlockView({required this.block, required this.onOpenLink});

  final LegalBlock block;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final body = textTheme.bodyMedium?.copyWith(
      color: AppColors.textStrong,
      height: 1.5,
    );
    return switch (block) {
      LegalSubheading(:final text) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xxs),
          child: Text(
            text,
            style: textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      LegalParagraph(:final spans) => _LegalRichText(
          spans: spans,
          style: body,
          onOpenLink: onOpenLink,
        ),
      LegalBulletList(:final items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        top: AppSpacing.s10,
                        right: AppSpacing.s10,
                        left: AppSpacing.xxs,
                      ),
                      child: Container(
                        width: AppSpacing.s6,
                        height: AppSpacing.s6,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _LegalRichText(
                        spans: item,
                        style: body,
                        onOpenLink: onOpenLink,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      LegalTable(:final header, :final rows) => Column(
          children: [
            for (final row in rows)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (row.isNotEmpty)
                      _LegalRichText(
                        spans: [
                          for (final s in row.first)
                            LegalSpan(s.text, bold: true, url: s.url),
                        ],
                        style: body?.copyWith(color: AppColors.textPrimary),
                        onOpenLink: onOpenLink,
                      ),
                    for (var c = 1; c < row.length; c++) ...[
                      const SizedBox(height: AppSpacing.xs),
                      if (c < header.length)
                        Text(
                          header[c],
                          style: textTheme.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      _LegalRichText(
                        spans: row[c],
                        style: body,
                        onOpenLink: onOpenLink,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
    };
  }
}

/// Texto com negrito e ligações tocáveis (sublinhadas, a verde).
class _LegalRichText extends StatefulWidget {
  const _LegalRichText({
    required this.spans,
    required this.style,
    required this.onOpenLink,
  });

  final List<LegalSpan> spans;
  final TextStyle? style;
  final ValueChanged<String> onOpenLink;

  @override
  State<_LegalRichText> createState() => _LegalRichTextState();
}

class _LegalRichTextState extends State<_LegalRichText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final children = <InlineSpan>[];
    for (final s in widget.spans) {
      final url = s.url;
      TapGestureRecognizer? recognizer;
      if (url != null) {
        recognizer = TapGestureRecognizer()..onTap = () => widget.onOpenLink(url);
        _recognizers.add(recognizer);
      }
      children.add(
        TextSpan(
          text: s.text,
          recognizer: recognizer,
          style: TextStyle(
            fontWeight: s.bold ? FontWeight.w700 : null,
            color: url != null
                ? AppColors.primary
                : (s.bold ? AppColors.textPrimary : null),
            decoration: url != null ? TextDecoration.underline : null,
            decorationColor: AppColors.primary,
          ),
        ),
      );
    }
    return Text.rich(TextSpan(style: widget.style, children: children));
  }
}
