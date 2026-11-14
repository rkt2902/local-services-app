import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/config/app_links.dart';
import 'package:servicesapp/core/widgets/app_legal_links.dart';

/// Termos e Política de Privacidade: links por omissão e toque na frase
/// do registo e do login social.
void main() {
  test('links por omissão: páginas do domínio e email do projeto', () {
    expect(AppLinks.termsUrl, 'https://projardim.pt/termos');
    expect(AppLinks.privacyPolicyUrl, 'https://projardim.pt/privacidade');
    expect(AppLinks.termsUrl, isNot(AppLinks.privacyPolicyUrl));
    expect(AppLinks.supportEmail, 'suporte@projardim.pt');
    expect(AppLinks.supportEmailOrDefault('Noth'), 'suporte@projardim.pt');
    expect(AppLinks.supportEmailOrDefault(' ajuda@projardim.pt '),
        'ajuda@projardim.pt');
  });

  testWidgets('cada nome abre a sua página', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppLegalConsentText(
          prefix: 'Aceito os ',
          onTermsPressed: () => opened.add('terms'),
          onPrivacyPressed: () => opened.add('privacy'),
        ),
      ),
    ));

    expect(
      find.text('Aceito os Termos e a Política de Privacidade.',
          findRichText: true),
      findsOneWidget,
    );

    await tester.tapOnText(find.textRange.ofSubstring('Termos'));
    await tester.tapOnText(find.textRange.ofSubstring('Política de Privacidade'));
    expect(opened, ['terms', 'privacy']);
  });
}
