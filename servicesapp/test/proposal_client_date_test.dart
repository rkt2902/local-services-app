import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/jobs/application/job_labels.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';

JobRequest _job({
  DateMode mode = DateMode.fixed,
  DateTime? date,
  String? availability,
}) =>
    JobRequest(
      id: 'job-1',
      clientId: 'client',
      serviceTypeId: 'relva',
      addressText: 'Braga',
      locationLat: 41.55,
      locationLng: -8.42,
      description: 'Relva.',
      status: JobStatus.open,
      dateMode: mode,
      preferredDate: date,
      availabilityText: availability,
      expiresAt: DateTime(2026, 12, 1),
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  final now = DateTime(2026, 10, 26, 15, 30);

  group('proposalInitialDate', () {
    test('usa a data do cliente quando ainda não passou', () {
      expect(proposalInitialDate(_job(date: DateTime(2026, 10, 30)), now),
          DateTime(2026, 10, 30));
    });

    test('a data de hoje conta, mesmo com a hora já passada', () {
      expect(proposalInitialDate(_job(date: DateTime(2026, 10, 26)), now),
          DateTime(2026, 10, 26));
    });

    test('data passada não pré-preenche', () {
      expect(proposalInitialDate(_job(date: DateTime(2026, 10, 25)), now),
          isNull);
    });

    test('sem data ou só disponibilidade não pré-preenche', () {
      expect(proposalInitialDate(_job(mode: DateMode.flexible), now), isNull);
      expect(
          proposalInitialDate(
              _job(mode: DateMode.availability, availability: 'Sábados'),
              now),
          isNull);
    });
  });

  group('jobPreferredDateLabel', () {
    test('data fixa, flexível e disponibilidade', () {
      expect(jobPreferredDateLabel(_job(date: DateTime(2026, 10, 30))),
          '30/10/2026');
      expect(jobPreferredDateLabel(_job(mode: DateMode.flexible)), 'Flexível');
      expect(
          jobPreferredDateLabel(
              _job(mode: DateMode.availability, availability: ' Sábados ')),
          'Sábados');
      expect(jobPreferredDateLabel(_job(mode: DateMode.availability)),
          'A combinar');
    });
  });
}
