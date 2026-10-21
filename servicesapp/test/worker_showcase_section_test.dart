import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/worker/data/worker_showcase.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_showcase_section.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('mostra apresentação, destaques e links', (tester) async {
    await tester.pumpWidget(_wrap(const WorkerShowcaseSection(
      bio: 'Jardineiro em Braga.',
      highlights: ['10 anos de experiência', 'Empresa com seguro'],
      socialLinks: [
        WorkerSocialLink(
          kind: WorkerSocialLinkKind.instagram,
          url: 'https://www.instagram.com/ojardim',
        ),
        WorkerSocialLink(
          kind: WorkerSocialLinkKind.other,
          url: 'https://www.tiktok.com/@ojardim',
        ),
      ],
    )));

    expect(find.text('Sobre'), findsOneWidget);
    expect(find.text('Em destaque'), findsOneWidget);
    expect(find.text('Empresa com seguro'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('TikTok'), findsOneWidget);
    expect(find.text('Informação partilhada pelo jardineiro.'), findsOneWidget);
  });

  testWidgets('sem nada preenchido não ocupa espaço', (tester) async {
    await tester.pumpWidget(_wrap(const WorkerShowcaseSection(
      bio: '  ',
      highlights: [],
      socialLinks: [],
    )));
    expect(find.text('Informação partilhada pelo jardineiro.'), findsNothing);
  });
}
