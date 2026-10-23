import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/utils/price_labels.dart';
import 'package:servicesapp/features/proposals/application/proposal_price_labels.dart';
import 'package:servicesapp/features/proposals/data/proposal_model.dart';
import 'package:servicesapp/features/worker/data/worker_job_board_entry_model.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_jobs_view.dart'
    as view;
import 'package:servicesapp/features/worker/presentation/worker_jobs_screen.dart';

/// O total estimado tem de incluir a equipa em todos os ecrãs: a mesma
/// conta ([teamHourlyRate]) no formulário, nas propostas recebidas, no
/// trabalho confirmado e em "Os meus trabalhos".
void main() {
  group('teamHourlyRate', () {
    test('sozinho é o preço por hora', () {
      expect(teamHourlyRate(20), 20);
    });

    test('ajudantes sem equipamento contam a 0,75', () {
      expect(teamHourlyRate(20, peopleNeeded: 3), 50);
    });

    test('ajudantes com equipamento contam por inteiro', () {
      expect(
        teamHourlyRate(20, peopleNeeded: 3, helpersEquipmentRequired: true),
        60,
      );
    });
  });

  group('estimatedTotalLabel e agreedPriceLabel', () {
    test('incluem a equipa', () {
      expect(estimatedTotalLabel(20, 2, 4, peopleNeeded: 3), '≈ 100 a 200 €');
      expect(
        agreedPriceLabel(
          20,
          2,
          4,
          peopleNeeded: 2,
          helpersEquipmentRequired: true,
        ),
        '20,00 €/h · ≈ 80 a 160 €',
      );
    });

    test('sem equipa fica igual ao que era', () {
      expect(estimatedTotalLabel(20, 2, 4), '≈ 40 a 80 €');
      expect(estimatedTotalLabel(20, null, null, peopleNeeded: 3), '');
    });
  });

  test('propostas recebidas usam a mesma conta', () {
    final p = JobProposal(
      id: 'p',
      jobId: 'j',
      workerId: 'w',
      hourlyRate: 20,
      estimatedHoursMin: 2,
      estimatedHoursMax: 4,
      peopleNeeded: 3,
      status: ProposalStatus.pending,
      createdAt: DateTime(2026, 10, 20),
    );
    expect(proposalTotalLabel(p), 'cerca de 100 a 200 €');
  });

  test('"Os meus trabalhos" inclui a equipa na proposta pendente', () {
    final e = WorkerJobBoardEntry.fromJson({
      'entry_id': 'e',
      'role': 'responsible',
      'job_id': 'j',
      'service_type_name': 'Corte de relva',
      'person_name': 'Ana',
      'address_text': 'Cascais',
      'hourly_rate': 20,
      'estimated_hours_min': 2,
      'estimated_hours_max': 4,
      'status': 'pending',
      'created_at': '2026-10-20T10:00:00Z',
      'job_status': 'open',
      'people_needed': 3,
      'helpers_equipment_required': false,
    });
    expect(e.peopleNeeded, 3);
    final text = workerJobCardText(
      e,
      view.WorkerJobsTab.pending,
      DateTime(2026, 10, 22),
    );
    expect(text.amount, '≈ 100 a 200 €');
  });

  test('sem as colunas novas (antes da 0056) conta como sozinho', () {
    final e = WorkerJobBoardEntry.fromJson({
      'entry_id': 'e',
      'role': 'responsible',
      'job_id': 'j',
      'status': 'pending',
      'created_at': '2026-10-20T10:00:00Z',
    });
    expect(e.peopleNeeded, 1);
    expect(e.helpersEquipmentRequired, false);
  });
}
