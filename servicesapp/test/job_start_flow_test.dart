import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/jobs/application/client_job_next_step.dart';
import 'package:servicesapp/features/jobs/application/job_timeline.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';
import 'package:servicesapp/features/worker/application/worker_job_rules.dart';

JobRequest _job({
  DateTime? date,
  String? time,
  bool flexible = false,
  DateTime? startedAt,
}) =>
    JobRequest(
      id: 'j',
      clientId: 'client',
      serviceTypeId: 's',
      addressText: '',
      locationLat: 0,
      locationLng: 0,
      description: '',
      status: JobStatus.confirmed,
      confirmedDate: date,
      confirmedTime: time,
      confirmedFlexible: flexible,
      startedAt: startedAt,
      expiresAt: DateTime(2026, 12, 1),
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  group('iniciar trabalho', () {
    final day = DateTime(2026, 10, 20);

    test('com hora, abre 1h antes', () {
      bool can(DateTime now) => WorkerJobDayRules.canStart(
            confirmedDate: day,
            confirmedTime: '14:00:00',
            confirmedFlexible: false,
            now: now,
          );
      expect(can(DateTime(2026, 10, 20, 12, 59)), isFalse);
      expect(can(DateTime(2026, 10, 20, 13, 0)), isTrue);
      expect(can(DateTime(2026, 10, 21, 9, 0)), isTrue);
    });

    test('sem hora ou flexível, abre no próprio dia', () {
      expect(
        WorkerJobDayRules.startOpensAt(
          confirmedDate: day,
          confirmedTime: null,
          confirmedFlexible: false,
        ),
        day,
      );
      expect(
        WorkerJobDayRules.startOpensAt(
          confirmedDate: day,
          confirmedTime: '14:00',
          confirmedFlexible: true,
        ),
        day,
      );
    });

    test('sem data, pode sempre', () {
      expect(
        WorkerJobDayRules.canStart(
          confirmedDate: null,
          confirmedTime: null,
          confirmedFlexible: false,
          now: DateTime(2026, 1, 1),
        ),
        isTrue,
      );
    });
  });

  test('durationLabel', () {
    expect(durationLabel(const Duration(hours: 2, minutes: 10)), '2h 10min');
    expect(durationLabel(const Duration(minutes: 45)), '45min');
    expect(durationLabel(const Duration(hours: 3)), '3h');
  });

  test('scheduledCountdownLabel', () {
    final now = DateTime(2026, 10, 20, 9, 41);
    expect(
      scheduledCountdownLabel(
          _job(date: DateTime(2026, 10, 20), time: '14:00:00'), now),
      'Hoje às 14:00 · daqui a 4h 19min',
    );
    expect(
      scheduledCountdownLabel(
          _job(date: DateTime(2026, 10, 21), time: '08:00'), now),
      'Amanhã às 08:00 · daqui a 22h 19min',
    );
    expect(scheduledCountdownLabel(_job(), now), 'Data a combinar');
  });

  test('em curso: timeline e próximo passo do cliente', () {
    final job = _job(
      date: DateTime(2026, 10, 20),
      time: '14:00',
      startedAt: DateTime(2026, 10, 20, 14, 5),
    );
    expect(job.isInProgress, isTrue);
    expect(clientJobNextStepLabel(job), 'O jardineiro já começou o trabalho.');
    final steps = buildJobTimeline(job, now: DateTime(2026, 10, 20, 15));
    expect(steps.map((s) => s.label),
        ['Aceite', 'Agendado', 'Em curso', 'Concluído']);
  });
}
