import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/constants/password_policy.dart';
import 'package:servicesapp/core/utils/date_labels.dart';
import 'package:servicesapp/core/utils/error_utils.dart';
import 'package:servicesapp/core/utils/price_labels.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('agreedPriceLabel', () {
    test('sem preço', () {
      expect(agreedPriceLabel(0, 2, 4), 'Preço a definir');
    });

    test('só o preço por hora quando não há horas', () {
      expect(agreedPriceLabel(25, null, null), '25,00 €/h');
    });

    test('intervalo de horas', () {
      expect(agreedPriceLabel(25, 2, 4), '25,00 €/h · ≈ 50 a 100 €');
    });

    test('uma só estimativa de horas', () {
      expect(estimatedTotalLabel(12.5, 3, null), '≈ 38 €');
      expect(estimatedTotalLabel(12.5, null, 2), '≈ 25 €');
      expect(estimatedTotalLabel(10, 3, 3), '≈ 30 €');
    });
  });

  group('preços com vírgula', () {
    test('preço por hora e horas', () {
      expect(hourlyRateLabel(25), '25,00 €/h');
      expect(hourlyRateLabel(0), 'Preço a definir');
      expect(estimatedHoursLabel(1.5, 3), '1,5 - 3,0 h');
      expect(estimatedHoursLabel(null, 2), '2,0 h');
      expect(estimatedHoursLabel(null, null), '');
      expect(decimalLabel(4.25, 1), '4,3');
    });
  });

  group('jobDeadlineLabel', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 15);

    test('modos sem data', () {
      expect(jobDeadlineLabel(DateMode.flexible, null), 'Flexível');
      expect(jobDeadlineLabel(DateMode.availability, null), 'Ver disponibilidade');
      expect(
        jobDeadlineLabel(DateMode.availability, null, availabilityText: '  '),
        'Ver disponibilidade',
      );
      expect(
        jobDeadlineLabel(
          DateMode.availability,
          null,
          availabilityText: 'Sábados de manhã',
        ),
        'Sábados de manhã',
      );
      // O texto só conta no modo disponibilidade.
      expect(
        jobDeadlineLabel(DateMode.flexible, null, availabilityText: 'x'),
        'Flexível',
      );
      expect(jobDeadlineLabel(DateMode.fixed, null), 'Data a combinar');
    });

    test('hoje, amanhã e outra data', () {
      expect(jobDeadlineLabel(DateMode.fixed, today), 'Hoje');
      expect(
        jobDeadlineLabel(DateMode.fixed, today.add(const Duration(days: 1))),
        'Amanhã',
      );
      expect(jobDeadlineLabel(DateMode.fixed, DateTime(2030, 3, 7)), '07/03/2030');
    });
  });

  group('política de password', () {
    test('força conforme as regras cumpridas', () {
      expect(evaluatePasswordPolicy('abc').strength, PasswordStrength.weak);
      expect(evaluatePasswordPolicy('abcdefgh1').strength, PasswordStrength.medium);
      expect(evaluatePasswordPolicy('Abcdefg1').strength, PasswordStrength.strong);
    });
  });

  group('friendlyError', () {
    test('falha de rede', () {
      expect(
        friendlyError(AuthRetryableFetchException()),
        startsWith('Sem ligação à internet'),
      );
      expect(
        friendlyError(Exception('SocketException: Failed host lookup')),
        startsWith('Sem ligação à internet'),
      );
    });

    test('erros de autenticação', () {
      expect(
        friendlyError(const AuthException('Invalid login credentials')),
        'Email ou password incorretos.',
      );
      expect(
        friendlyError(const AuthException('Email not confirmed')),
        startsWith('Confirma o teu email'),
      );
      expect(
        friendlyError(const AuthException('over_email_send_rate_limit')),
        startsWith('Demasiadas tentativas'),
      );
    });

    test('email já registado', () {
      expect(
        friendlyError(const AuthException('User already registered')),
        'Este email já está registado.',
      );
    });

    test('regra da véspera de cancelar e remarcar', () {
      expect(
        friendlyError(Exception(
            'O cancelamento requer pelo menos 24h de antecedência.')),
        'Só podes cancelar até à véspera do trabalho.',
      );
      expect(
        friendlyError(Exception(
            'Não pode remarcar com menos de 24h de antecedência')),
        'Só podes remarcar até à véspera do trabalho.',
      );
    });

    test('remarcação pendente', () {
      expect(
        friendlyError(Exception('Já existe uma remarcação pendente')),
        'Já existe uma remarcação pendente. Espera pela resposta.',
      );
      expect(
        friendlyError(Exception('Sem remarcação pendente')),
        startsWith('Esta remarcação já foi respondida'),
      );
    });

    test('desconhecido dá mensagem genérica, nunca texto técnico', () {
      expect(
        friendlyError(Exception('PGRST999 something odd')),
        'Ocorreu um erro inesperado. Tenta novamente.',
      );
    });
  });

  group('enums da BD', () {
    test('ida e volta de todos os valores', () {
      for (final s in JobStatus.values) {
        expect(JobStatus.fromValue(s.value), s);
      }
      for (final s in ProposalStatus.values) {
        expect(ProposalStatus.fromValue(s.value), s);
      }
      for (final s in HelpRequestStatus.values) {
        expect(HelpRequestStatus.fromValue(s.value), s);
      }
      for (final s in HelpAcceptanceStatus.values) {
        expect(HelpAcceptanceStatus.fromValue(s.value), s);
      }
      for (final r in UserRole.values) {
        expect(UserRole.fromValue(r.value), r);
      }
    });

    test('proposal_received antigo conta como open', () {
      expect(JobStatus.fromValue('proposal_received'), JobStatus.open);
    });

    test('valor desconhecido falha alto', () {
      expect(() => JobStatus.fromValue('xyz'), throwsArgumentError);
    });
  });

  group('rpcErrorMessage', () {
    const unavailable = 'Ainda não disponível.';

    test('função em falta (migration por aplicar)', () {
      const e = PostgrestException(message: 'Could not find', code: 'PGRST202');
      expect(isMissingRpcError(e), isTrue);
      expect(rpcErrorMessage(e, unavailableMessage: unavailable), unavailable);
    });

    test('recusa da própria função mostra a mensagem dela', () {
      const e = PostgrestException(
        message: 'Tens trabalhos em curso.',
        code: 'P0001',
      );
      expect(isMissingRpcError(e), isFalse);
      expect(
        rpcErrorMessage(e, unavailableMessage: unavailable),
        'Tens trabalhos em curso.',
      );
    });

    test('o resto passa por friendlyError', () {
      expect(
        rpcErrorMessage(
          Exception('SocketException: Failed host lookup'),
          unavailableMessage: unavailable,
        ),
        startsWith('Sem ligação'),
      );
    });
  });
}
