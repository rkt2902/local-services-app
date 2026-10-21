import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/client/application/client_create_job_wizard_provider.dart';
import 'package:servicesapp/features/jobs/application/job_labels.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';

JobRequest _openJob({
  int proposalCount = 0,
  DateMode dateMode = DateMode.flexible,
  DateTime? preferredDate,
}) =>
    JobRequest(
      id: 'j1',
      clientId: 'c1',
      serviceTypeId: 's1',
      addressText: 'Rua A, Braga',
      locationLat: 0,
      locationLng: 0,
      description: 'Cortar a relva',
      status: JobStatus.open,
      proposalCount: proposalCount,
      dateMode: dateMode,
      preferredDate: preferredDate,
      expiresAt: DateTime(2026, 10, 20, 14, 30),
      createdAt: DateTime(2026, 10, 18, 14, 30),
    );

void main() {
  group('isOnOrAfterJobDay (regra do servidor, por datas)', () {
    final now = DateTime(2026, 10, 18, 23, 0);

    test('sem data confirmada nunca bloqueia', () {
      expect(isOnOrAfterJobDay(null, now), isFalse);
    });

    test('amanhã ainda se pode, mesmo a menos de 24h', () {
      expect(isOnOrAfterJobDay(DateTime(2026, 10, 19), now), isFalse);
    });

    test('no próprio dia e depois já não', () {
      expect(isOnOrAfterJobDay(DateTime(2026, 10, 18), now), isTrue);
      expect(isOnOrAfterJobDay(DateTime(2026, 10, 17), now), isTrue);
    });

    test('ignora a hora da data confirmada', () {
      expect(
        isOnOrAfterJobDay(DateTime(2026, 10, 19, 1), DateTime(2026, 10, 18, 2)),
        isFalse,
      );
    });
  });

  group('openJobExpiryNotice (auto_expire_jobs, 0046)', () {
    test('sem propostas: expira às 48h', () {
      expect(
        openJobExpiryNotice(_openJob()),
        'Expira a 20/10 às 14:30 se não receber nenhuma proposta.',
      );
    });

    test('com propostas e sem data fixa: não expira sozinho', () {
      expect(openJobExpiryNotice(_openJob(proposalCount: 2)), isNull);
    });

    test('data fixa com propostas: expira se a data passar', () {
      expect(
        openJobExpiryNotice(_openJob(
          proposalCount: 1,
          dateMode: DateMode.fixed,
          preferredDate: DateTime(2026, 10, 25),
        )),
        'Expira se nenhuma proposta for aceite até 25/10.',
      );
    });

    test('data fixa sem propostas: as duas regras', () {
      expect(
        openJobExpiryNotice(_openJob(
          dateMode: DateMode.fixed,
          preferredDate: DateTime(2026, 10, 25),
        )),
        'Expira a 20/10 às 14:30 se não receber nenhuma proposta, '
        'ou se nenhuma for aceite até 25/10.',
      );
    });
  });

  group('rascunho do pedido', () {
    test('copyWith deixa apagar a localidade e mantém-na se omitida', () {
      const draft = ClientCreateJobWizardState(locationArea: 'Braga');
      expect(draft.copyWith(addressText: 'x').locationArea, 'Braga');
      expect(draft.copyWith(locationArea: null).locationArea, isNull);
      expect(draft.copyWith(locationArea: 'Porto').locationArea, 'Porto');
    });
  });
}
