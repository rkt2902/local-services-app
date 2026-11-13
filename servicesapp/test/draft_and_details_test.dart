import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/jobs/application/job_timeline.dart';
import 'package:servicesapp/features/client/application/client_create_job_wizard_provider.dart';
import 'package:servicesapp/features/client/data/create_job_draft_store.dart';

void main() {
  final now = DateTime(2026, 11, 13, 10);

  group('Rascunho do pedido guardado no dispositivo', () {
    test('ida e volta mantém os campos', () {
      final s = ClientCreateJobWizardState(
        serviceTypeId: 'svc',
        dateMode: DateMode.fixed,
        preferredDate: DateTime(2026, 11, 20),
        urgency: Urgency.urgent,
        sizeEstimate: SizeEstimate.medium,
        addressText: 'Rua A 1',
        locationArea: 'Lisboa',
        locationLat: 38.7,
        locationLng: -9.1,
        description: 'Cortar a relva',
      );
      final back = createJobDraftFromJson(
        createJobDraftToJson(s, now: now)!,
        now: now,
      )!;
      expect(back.serviceTypeId, 'svc');
      expect(back.dateMode, DateMode.fixed);
      expect(back.preferredDate, DateTime(2026, 11, 20));
      expect(back.urgency, Urgency.urgent);
      expect(back.sizeEstimate, SizeEstimate.medium);
      expect(back.addressText, 'Rua A 1');
      expect(back.locationLat, 38.7);
      expect(back.description, 'Cortar a relva');
    });

    test('vazio não se guarda', () {
      expect(
        createJobDraftToJson(const ClientCreateJobWizardState(), now: now),
        isNull,
      );
    });

    test('pedido direto não se guarda', () {
      const s = ClientCreateJobWizardState(
        serviceTypeId: 'svc',
        directCardWorkerId: 'w',
      );
      expect(createJobDraftToJson(s, now: now), isNull);
    });

    test('data que já passou é apagada', () {
      final json = createJobDraftToJson(
        ClientCreateJobWizardState(
          serviceTypeId: 'svc',
          dateMode: DateMode.fixed,
          preferredDate: DateTime(2026, 11, 14),
        ),
        now: now,
      )!;
      final later = DateTime(2026, 11, 16);
      final back = createJobDraftFromJson(json, now: later)!;
      expect(back.preferredDate, isNull);
      expect(back.serviceTypeId, 'svc');
    });

    test('com mais de 7 dias não volta', () {
      final json = createJobDraftToJson(
        const ClientCreateJobWizardState(serviceTypeId: 'svc'),
        now: now,
      )!;
      expect(
        createJobDraftFromJson(json, now: now.add(const Duration(days: 8))),
        isNull,
      );
    });
  });

  test('tempo registado abaixo de 1 minuto', () {
    expect(durationLabel(const Duration(seconds: 20)), 'menos de 1min');
    expect(durationLabel(const Duration(minutes: 1)), '1min');
  });
}
