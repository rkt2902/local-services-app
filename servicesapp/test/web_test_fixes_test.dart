import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/jobs/application/job_labels.dart';
import 'package:servicesapp/features/jobs/data/job_repository.dart';

void main() {
  group('W-3: prazo da confirmação automática', () {
    final done = DateTime(2026, 11, 12, 15);

    test('sem relato: 48 horas', () {
      final text = clientAutoConfirmHint(
        markedDoneAt: done,
        myLatestReportAt: null,
      );
      expect(text, contains('48 horas'));
      expect(text, isNot(contains('7 dias')));
    });

    test('com relato depois de concluir: 7 dias e a data', () {
      final text = clientAutoConfirmHint(
        markedDoneAt: done,
        myLatestReportAt: done.add(const Duration(hours: 1)),
      );
      expect(text, startsWith('Recebemos o teu relato.'));
      expect(text, contains('7 dias'));
      expect(text, contains('(a 19/11)'));
    });

    test('relato antigo, de antes de concluir, não conta', () {
      final text = clientAutoConfirmHint(
        markedDoneAt: done,
        myLatestReportAt: done.subtract(const Duration(days: 1)),
      );
      expect(text, contains('48 horas'));
    });
  });

  group('W-4: horas sem segundos', () {
    test('tira os segundos do time do Postgres', () {
      expect(shortTimeLabel('09:00:00'), '09:00');
      expect(shortTimeLabel('14:30'), '14:30');
      expect(shortTimeLabel('9h'), '9h');
    });
  });

  group('W-10: RPC sem linhas devolve null', () {
    test('lista vazia', () => expect(firstRpcRow(const []), isNull));
    test('null', () => expect(firstRpcRow(null), isNull));
    test('primeira linha', () {
      expect(firstRpcRow([
        {'id': 'a'},
        {'id': 'b'},
      ]), {'id': 'a'});
    });
    test('objeto', () => expect(firstRpcRow({'id': 'a'}), {'id': 'a'}));
  });
}
