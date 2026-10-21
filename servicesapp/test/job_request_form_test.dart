import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/client/application/client_create_job_wizard_provider.dart';
import 'package:servicesapp/features/client/application/job_request_form.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';

final _now = DateTime(2026, 10, 18, 15, 0);

JobRequest _job({
  JobStatus status = JobStatus.noResponse,
  DateMode dateMode = DateMode.flexible,
  DateTime? preferredDate,
  String? availabilityText,
  SizeEstimate? sizeEstimate = SizeEstimate.medium,
  String description = 'Cortar a relva do quintal',
  String? acceptedProposalId,
  String? cancelledBy,
  double lat = 41.55,
  double lng = -8.42,
  Urgency? urgency,
}) =>
    JobRequest(
      id: 'j1',
      clientId: 'c1',
      serviceTypeId: 's1',
      addressText: 'Rua A 1, Braga',
      locationArea: 'Braga',
      locationLat: lat,
      locationLng: lng,
      dateMode: dateMode,
      preferredDate: preferredDate,
      availabilityText: availabilityText,
      urgency: urgency,
      sizeEstimate: sizeEstimate,
      description: description,
      status: status,
      acceptedProposalId: acceptedProposalId,
      cancelledBy: cancelledBy,
      expiresAt: DateTime(2026, 10, 10),
      createdAt: DateTime(2026, 10, 8),
    );

void main() {
  group('canRepublishJob', () {
    test('sem resposta pode', () {
      expect(canRepublishJob(_job(status: JobStatus.noResponse)), isTrue);
    });

    test('cancelado pelo cliente ainda aberto pode', () {
      expect(
        canRepublishJob(_job(status: JobStatus.cancelled, cancelledBy: 'c1')),
        isTrue,
      );
      expect(canRepublishJob(_job(status: JobStatus.cancelled)), isTrue);
    });

    test('cancelado com proposta aceite ou por outra pessoa não pode', () {
      expect(
        canRepublishJob(_job(
          status: JobStatus.cancelled,
          cancelledBy: 'c1',
          acceptedProposalId: 'p1',
        )),
        isFalse,
      );
      expect(
        canRepublishJob(_job(status: JobStatus.cancelled, cancelledBy: 'w1')),
        isFalse,
      );
    });

    test('outros estados não podem', () {
      for (final status in [
        JobStatus.open,
        JobStatus.confirmed,
        JobStatus.awaitingConfirmation,
        JobStatus.completed,
      ]) {
        expect(canRepublishJob(_job(status: status)), isFalse,
            reason: status.value);
      }
    });
  });

  group('republishWizardState', () {
    test('copia serviço, morada, localização, descrição e dimensão', () {
      final s = republishWizardState(
        _job(urgency: Urgency.urgent),
        now: _now,
      );
      expect(s.serviceTypeId, 's1');
      expect(s.addressText, 'Rua A 1, Braga');
      expect(s.addressAutoFilled, isFalse);
      expect(s.locationArea, 'Braga');
      expect(s.locationLat, 41.55);
      expect(s.locationLng, -8.42);
      expect(s.description, 'Cortar a relva do quintal');
      expect(s.sizeEstimate, SizeEstimate.medium);
      expect(s.urgency, Urgency.urgent);
      expect(s.dateMode, DateMode.flexible);
      expect(s.photos, isEmpty);
    });

    test('data fixa no futuro (ou hoje) mantém-se', () {
      final future = republishWizardState(
        _job(dateMode: DateMode.fixed, preferredDate: DateTime(2026, 10, 25)),
        now: _now,
      );
      expect(future.dateMode, DateMode.fixed);
      expect(future.preferredDate, DateTime(2026, 10, 25));

      final today = republishWizardState(
        _job(dateMode: DateMode.fixed, preferredDate: DateTime(2026, 10, 18)),
        now: _now,
      );
      expect(today.preferredDate, DateTime(2026, 10, 18));
    });

    test('data fixa que já passou fica vazia', () {
      final s = republishWizardState(
        _job(dateMode: DateMode.fixed, preferredDate: DateTime(2026, 10, 17)),
        now: _now,
      );
      expect(s.dateMode, DateMode.fixed);
      expect(s.preferredDate, isNull);
    });

    test('disponibilidade leva o texto', () {
      final s = republishWizardState(
        _job(
          dateMode: DateMode.availability,
          availabilityText: ' Sábados de manhã ',
        ),
        now: _now,
      );
      expect(s.dateMode, DateMode.availability);
      expect(s.availabilityText, 'Sábados de manhã');
    });

    test('serviço fora do catálogo fica por escolher', () {
      final s = republishWizardState(
        _job(),
        now: _now,
        serviceStillOffered: false,
      );
      expect(s.serviceTypeId, isNull);
    });

    test('sem coordenadas, sem pin', () {
      final s = republishWizardState(_job(lat: 0, lng: 0), now: _now);
      expect(s.locationLat, isNull);
      expect(s.locationLng, isNull);
    });
  });

  group('wizardFirstIncompleteRoute', () {
    String route(JobRequest job, {bool serviceStillOffered = true}) =>
        wizardFirstIncompleteRoute(republishWizardState(
          job,
          now: _now,
          serviceStillOffered: serviceStillOffered,
        ));

    test('tudo preenchido vai para a revisão', () {
      expect(route(_job()), '/client/create-job/review');
      expect(
        route(_job(
          dateMode: DateMode.availability,
          availabilityText: 'Sábados',
        )),
        '/client/create-job/review',
      );
    });

    test('serviço em falta começa no passo 1', () {
      expect(route(_job(), serviceStillOffered: false), '/client/create-job');
    });

    test('data passada, dimensão, pin ou disponibilidade em falta: passo 2',
        () {
      expect(
        route(_job(
          dateMode: DateMode.fixed,
          preferredDate: DateTime(2026, 10, 1),
        )),
        '/client/create-job/schedule',
      );
      expect(route(_job(sizeEstimate: null)), '/client/create-job/schedule');
      expect(route(_job(lat: 0, lng: 0)), '/client/create-job/schedule');
      expect(
        route(_job(dateMode: DateMode.availability)),
        '/client/create-job/schedule',
      );
    });

    test('descrição curta demais: passo 3', () {
      expect(route(_job(description: 'curta')),
          '/client/create-job/description');
    });

    test('rascunho vazio começa no passo 1', () {
      expect(
        wizardFirstIncompleteRoute(const ClientCreateJobWizardState()),
        '/client/create-job',
      );
    });
  });

  group('availabilityTextError', () {
    test('vazio e só espaços são erro', () {
      expect(availabilityTextError(''), isNotNull);
      expect(availabilityTextError('   '), isNotNull);
    });

    test('limite de caracteres', () {
      expect(
        availabilityTextError('a' * availabilityTextMaxLength),
        isNull,
      );
      expect(
        availabilityTextError('a' * (availabilityTextMaxLength + 1)),
        isNotNull,
      );
    });
  });
}
