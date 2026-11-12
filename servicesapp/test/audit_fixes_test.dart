import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/theme/app_colors.dart';
import 'package:servicesapp/features/jobs/presentation/widgets/client_proposal_detail_view.dart';
import 'package:servicesapp/features/onboarding/presentation/widgets/onboarding_page_indicator.dart';

/// Correções da auditoria de 12/11/2026 (docs/systematic-debugging-audit).
void main() {
  group('BUG-013: erros de accept_proposal', () {
    test('pedido já não aberto (0073) recarrega a lista', () {
      expect(classifyAcceptProposalError('Este pedido já não está aberto.'),
          ClientProposalAcceptOutcome.unavailable);
    });
    test('mensagens antigas continuam iguais', () {
      expect(
          classifyAcceptProposalError(
              'Este orçamento expirou e já não pode ser aceite.'),
          ClientProposalAcceptOutcome.expired);
      expect(
          classifyAcceptProposalError(
              'Este orçamento expirou: o dia proposto já passou.'),
          ClientProposalAcceptOutcome.expired);
      expect(
          classifyAcceptProposalError(
              'Proposta não encontrada ou já processada.'),
          ClientProposalAcceptOutcome.unavailable);
    });
    test('outros erros ficam genéricos', () {
      expect(
          classifyAcceptProposalError(
              'Não autorizado: só o cliente pode aceitar propostas.'),
          isNull);
    });
  });

  testWidgets('BUG-011: indicador do onboarding usa o token de cor',
      (tester) async {
    const indicator = OnboardingPageIndicator(currentPage: 0, pageCount: 3);
    expect(indicator.inactiveColor, AppColors.onboardingDotInactive);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: indicator)));
    expect(find.byType(OnboardingPageIndicator), findsOneWidget);
  });
}
