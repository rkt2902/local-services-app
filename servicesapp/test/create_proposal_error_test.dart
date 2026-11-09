import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/proposals/data/proposal_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('createProposalDuplicateError', () {
    test('proposta repetida vira a mensagem própria', () {
      const server = PostgrestException(
        message: 'Já tens uma proposta para este pedido.',
        code: 'P0001',
      );
      const race = PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
      for (final e in [server, race]) {
        expect(createProposalDuplicateError(e).toString(),
            contains('Já enviaste uma proposta'));
      }
    });

    test('outras recusas do servidor passam como estão', () {
      // Antes qualquer P0001 virava "Já enviaste uma proposta".
      const messages = [
        'Chegaste aos 5 trabalhos deste mês do plano Grátis.',
        'Este pedido já não está disponível.',
        'O dia proposto já passou. Escolhe hoje ou um dia a seguir.',
      ];
      for (final m in messages) {
        expect(
          createProposalDuplicateError(
              PostgrestException(message: m, code: 'P0001')),
          isNull,
        );
      }
    });
  });
}
