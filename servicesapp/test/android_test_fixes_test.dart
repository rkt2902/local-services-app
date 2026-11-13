import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/help_requests/data/help_request_model.dart';
import 'package:servicesapp/features/worker/presentation/worker_dashboard_screen.dart';

HelpAcceptanceSummary _a(
  String id, {
  HelpAcceptanceStatus status = HelpAcceptanceStatus.accepted,
  String jobStatus = 'confirmed',
  DateTime? date,
  String? time,
}) => HelpAcceptanceSummary(
  id: id,
  helpRequestId: 'hr-$id',
  status: status,
  agreedRate: 10.5,
  broughtEquipment: false,
  createdAt: DateTime(2026, 11, 1),
  serviceTypeName: 'Corte de relva',
  principalName: 'Rui',
  jobStatus: jobStatus,
  jobId: 'job-$id',
  confirmedDate: date,
  confirmedTime: time,
);

void main() {
  final today = DateTime(2026, 11, 13);

  group('F11 próximo trabalho como ajudante no Início', () {
    test('escolhe o aceite mais próximo de hoje em diante', () {
      final next = nextHelperJob([
        _a('depois', date: DateTime(2026, 11, 20)),
        _a('passado', date: DateTime(2026, 11, 10)),
        _a(
          'pendente',
          status: HelpAcceptanceStatus.pending,
          date: DateTime(2026, 11, 14),
        ),
        _a('feito', jobStatus: 'completed', date: DateTime(2026, 11, 14)),
        _a('amanha', date: DateTime(2026, 11, 14), time: '09:00:00'),
      ], today: today);
      expect(next?.id, 'amanha');
    });

    test('sem trabalhos de ajudante marcados: nada', () {
      expect(
        nextHelperJob([
          _a('x', status: HelpAcceptanceStatus.rejected, date: today),
        ], today: today),
        isNull,
      );
    });
  });

  group('F11 vagas que faltam no Descobrir', () {
    Map<String, dynamic> row({int? filled}) => {
      'id': 'hr',
      'job_id': 'job',
      'proposal_id': 'p',
      'slots_needed': 2,
      'status': 'open',
      'equipment_required': false,
      'created_post_confirmation': false,
      'created_at': '2026-11-13T10:00:00Z',
      'location_lat': 41.8,
      'location_lng': -6.75,
      'service_type_id': 'st',
      'principal_name': 'Rui',
      'slots_filled': ?filled,
    };

    test('com a 0077: 2 vagas e 1 aceite → falta 1', () {
      expect(HelpRequestSummary.fromJson(row(filled: 1)).slotsRemaining, 1);
    });

    test('antes da 0077 (sem slots_filled): conta as vagas todas', () {
      expect(HelpRequestSummary.fromJson(row()).slotsRemaining, 2);
    });
  });
}
