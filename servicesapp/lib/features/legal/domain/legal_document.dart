/// Termos de utilização e Política de Privacidade, lidos dos ficheiros
/// Markdown em `assets/legal/` (a mesma fonte das páginas web estáticas
/// `/termos` e `/privacidade`, geradas por `tool/build_legal_pages.py`).
///
/// Só o subconjunto de Markdown que os textos usam: `#`, `##`, `###`,
/// parágrafos, listas com `- `, tabelas com `|`, `---`, `**negrito**` e
/// `[texto](url)`.
library;

enum LegalDocumentKind {
  terms(
    route: '/termos',
    asset: 'assets/legal/termos-de-utilizacao.md',
    shortTitle: 'Termos de utilização',
  ),
  privacy(
    route: '/privacidade',
    asset: 'assets/legal/politica-de-privacidade.md',
    shortTitle: 'Política de Privacidade',
  );

  const LegalDocumentKind({
    required this.route,
    required this.asset,
    required this.shortTitle,
  });

  /// Rota da app e caminho da página web (`projardim.pt/termos`).
  final String route;
  final String asset;
  final String shortTitle;
}

/// Pedaço de texto com estilo: normal, negrito ou ligação.
class LegalSpan {
  const LegalSpan(this.text, {this.bold = false, this.url});

  final String text;
  final bool bold;
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is LegalSpan &&
      other.text == text &&
      other.bold == bold &&
      other.url == url;

  @override
  int get hashCode => Object.hash(text, bold, url);

  @override
  String toString() =>
      'LegalSpan($text${bold ? ', bold' : ''}${url != null ? ', $url' : ''})';
}

sealed class LegalBlock {
  const LegalBlock();
}

class LegalSubheading extends LegalBlock {
  const LegalSubheading(this.text);
  final String text;
}

class LegalParagraph extends LegalBlock {
  const LegalParagraph(this.spans);
  final List<LegalSpan> spans;
}

class LegalBulletList extends LegalBlock {
  const LegalBulletList(this.items);
  final List<List<LegalSpan>> items;
}

/// Tabela: [header] e [rows] com as células já divididas em spans.
class LegalTable extends LegalBlock {
  const LegalTable({required this.header, required this.rows});
  final List<String> header;
  final List<List<List<LegalSpan>>> rows;
}

class LegalSection {
  const LegalSection({required this.title, required this.blocks});

  /// Ex.: "4. Para que usamos os dados e com que fundamento legal".
  final String title;
  final List<LegalBlock> blocks;
}

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.updatedAt,
    required this.intro,
    required this.sections,
  });

  /// Sem o prefixo "ProJardim: ".
  final String title;

  /// Ex.: "13 de novembro de 2026", ou null se o texto não a tiver.
  final String? updatedAt;

  /// Blocos antes da primeira secção.
  final List<LegalBlock> intro;
  final List<LegalSection> sections;

  static final _updatedAt = RegExp(r'^\*\*Última atualização:\*\*\s*(.+)$');

  static LegalDocument parse(String markdown) {
    var title = '';
    String? updatedAt;
    final intro = <LegalBlock>[];
    final sections = <LegalSection>[];
    String? sectionTitle;
    var blocks = <LegalBlock>[];

    final paragraph = <String>[];
    final bullets = <String>[];
    final tableLines = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(LegalParagraph(parseInline(paragraph.join(' '))));
      paragraph.clear();
    }

    void flushBullets() {
      if (bullets.isEmpty) return;
      blocks.add(LegalBulletList([for (final b in bullets) parseInline(b)]));
      bullets.clear();
    }

    void flushTable() {
      if (tableLines.isEmpty) return;
      final rows = [
        for (final line in tableLines)
          if (!RegExp(r'^\|[\s\-:|]+\|?$').hasMatch(line)) _cells(line),
      ];
      if (rows.isNotEmpty) {
        blocks.add(
          LegalTable(
            header: [for (final c in rows.first) _plain(c)],
            rows: [
              for (final r in rows.skip(1)) [for (final c in r) parseInline(c)],
            ],
          ),
        );
      }
      tableLines.clear();
    }

    void flushAll() {
      flushParagraph();
      flushBullets();
      flushTable();
    }

    void closeSection() {
      flushAll();
      if (sectionTitle == null) {
        intro.addAll(blocks);
      } else {
        sections.add(LegalSection(title: sectionTitle, blocks: blocks));
      }
      blocks = <LegalBlock>[];
    }

    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        flushAll();
        title = trimmed.substring(2).trim();
        if (title.startsWith('ProJardim: ')) {
          title = title.substring('ProJardim: '.length);
        }
        continue;
      }
      final updated = _updatedAt.firstMatch(trimmed);
      if (updated != null) {
        flushAll();
        updatedAt = updated.group(1)!.trim();
        continue;
      }
      if (trimmed.startsWith('## ')) {
        closeSection();
        sectionTitle = trimmed.substring(3).trim();
        continue;
      }
      if (trimmed.startsWith('### ')) {
        flushAll();
        blocks.add(LegalSubheading(trimmed.substring(4).trim()));
        continue;
      }
      if (trimmed == '---' || trimmed.isEmpty) {
        flushAll();
        continue;
      }
      if (trimmed.startsWith('|')) {
        flushParagraph();
        flushBullets();
        tableLines.add(trimmed);
        continue;
      }
      if (trimmed.startsWith('- ')) {
        flushParagraph();
        flushTable();
        bullets.add(trimmed.substring(2).trim());
        continue;
      }
      if (bullets.isNotEmpty && line.startsWith('  ')) {
        bullets[bullets.length - 1] = '${bullets.last} $trimmed';
        continue;
      }
      flushBullets();
      flushTable();
      paragraph.add(trimmed);
    }
    closeSection();

    return LegalDocument(
      title: title,
      updatedAt: updatedAt,
      intro: intro,
      sections: sections,
    );
  }

  static List<String> _cells(String line) {
    var body = line.trim();
    if (body.startsWith('|')) body = body.substring(1);
    if (body.endsWith('|')) body = body.substring(0, body.length - 1);
    return [for (final c in body.split('|')) c.trim()];
  }

  static String _plain(String text) =>
      [for (final s in parseInline(text)) s.text].join();

  static final _inline = RegExp(r'\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)\s]+)\)');
  static final _bareEmail = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');

  /// `**negrito**` e `[texto](url)`; emails soltos viram `mailto:`.
  static List<LegalSpan> parseInline(String text) {
    final spans = <LegalSpan>[];
    var index = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > index) {
        spans.addAll(_withEmails(text.substring(index, m.start), bold: false));
      }
      if (m.group(1) != null) {
        spans.addAll(_withEmails(m.group(1)!, bold: true));
      } else {
        spans.add(LegalSpan(m.group(2)!, url: m.group(3)));
      }
      index = m.end;
    }
    if (index < text.length) {
      spans.addAll(_withEmails(text.substring(index), bold: false));
    }
    return spans;
  }

  static List<LegalSpan> _withEmails(String text, {required bool bold}) {
    final spans = <LegalSpan>[];
    var index = 0;
    for (final m in _bareEmail.allMatches(text)) {
      if (m.start > index) {
        spans.add(LegalSpan(text.substring(index, m.start), bold: bold));
      }
      spans.add(LegalSpan(m.group(0)!, bold: bold, url: 'mailto:${m.group(0)}'));
      index = m.end;
    }
    if (index < text.length) {
      spans.add(LegalSpan(text.substring(index), bold: bold));
    }
    return spans;
  }
}
