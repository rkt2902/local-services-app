import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/router/route_guard.dart';
import 'package:servicesapp/features/auth/application/session_provider.dart';
import 'package:servicesapp/features/legal/domain/legal_document.dart';
import 'package:servicesapp/features/legal/presentation/legal_document_screen.dart';

void main() {
  group('LegalDocument.parse', () {
    const md = '''
# ProJardim: Termos

**Última atualização:** 13 de novembro de 2026

Introdução com email suporte@projardim.pt.

---

## 1. Quem somos

Texto **forte** e [link](https://www.cnpd.pt).

### 1.1 Sub

- um
- dois

| Coluna A | Coluna B |
|---|---|
| **a1** | b1 |

## 2. Outra

Último.
''';

    test('título, data, introdução e secções', () {
      final d = LegalDocument.parse(md);
      expect(d.title, 'Termos');
      expect(d.updatedAt, '13 de novembro de 2026');
      expect(d.intro, hasLength(1));
      expect(d.sections.map((s) => s.title), ['1. Quem somos', '2. Outra']);
      final blocks = d.sections.first.blocks;
      expect(blocks[0], isA<LegalParagraph>());
      expect(blocks[1], isA<LegalSubheading>());
      expect((blocks[2] as LegalBulletList).items, hasLength(2));
      final table = blocks[3] as LegalTable;
      expect(table.header, ['Coluna A', 'Coluna B']);
      expect(table.rows, hasLength(1));
      expect(table.rows.first.first.first, const LegalSpan('a1', bold: true));
    });

    test('negrito, ligações e emails', () {
      final spans = LegalDocument.parseInline(
        'Ver **isto** em [CNPD](https://www.cnpd.pt) ou a@b.pt.',
      );
      expect(spans, [
        const LegalSpan('Ver '),
        const LegalSpan('isto', bold: true),
        const LegalSpan(' em '),
        const LegalSpan('CNPD', url: 'https://www.cnpd.pt'),
        const LegalSpan(' ou '),
        const LegalSpan('a@b.pt', url: 'mailto:a@b.pt'),
        const LegalSpan('.'),
      ]);
    });

    test('os textos reais têm data e todas as secções numeradas', () {
      for (final kind in LegalDocumentKind.values) {
        final d = LegalDocument.parse(File(kind.asset).readAsStringSync());
        expect(d.updatedAt, isNotNull, reason: kind.asset);
        expect(d.sections.length, greaterThan(10), reason: kind.asset);
        for (var i = 0; i < d.sections.length; i++) {
          expect(splitSectionTitle(d.sections[i].title).$1, '${i + 1}',
              reason: '${kind.asset}: ${d.sections[i].title}');
        }
      }
    });
  });

  group('rotas legais', () {
    test('abrem sem sessão, sem onboarding e com conta', () {
      for (final loc in ['/termos', '/privacidade']) {
        expect(
          resolveRedirect(
            location: loc,
            session: SessionStatus.unauthenticated,
            hasSeenOnboarding: false,
          ),
          isNull,
        );
      }
    });
  });

  testWidgets('ecrã mostra o cabeçalho, o índice e as secções', (tester) async {
    final d = LegalDocument.parse(
      File(LegalDocumentKind.privacy.asset).readAsStringSync(),
    );
    var other = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LegalDocumentView(
          kind: LegalDocumentKind.privacy,
          document: d,
          onOpenLink: (_) {},
          onOpenOther: () => other++,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Política de Privacidade'), findsOneWidget);
    expect(find.textContaining('Última atualização'), findsOneWidget);
    expect(find.text('Índice'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ler os Termos de utilização'),
      500,
    );
    await tester.tap(find.text('Ler os Termos de utilização'));
    expect(other, 1);
  });
}
