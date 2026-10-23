import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/features/proposals/application/proposal_price_labels.dart';
import 'package:servicesapp/features/proposals/data/proposal_model.dart';
import 'package:servicesapp/features/worker/data/worker_job_board_entry_model.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_jobs_view.dart'
    as view;
import 'package:servicesapp/features/worker/presentation/worker_jobs_screen.dart';

JobProposal _p({
  ProposalPricingMode mode = ProposalPricingMode.hourly,
  double rate = 25,
  double? total,
  double? hMin = 4,
  double? hMax = 6,
  int? dMin,
  int? dMax,
  List<String> includes = const [],
  DateTime? validUntil,
  bool expired = false,
}) =>
    JobProposal(
      id: 'p',
      jobId: 'j',
      workerId: 'w',
      hourlyRate: rate,
      estimatedHoursMin: hMin,
      estimatedHoursMax: hMax,
      peopleNeeded: 1,
      status: ProposalStatus.pending,
      createdAt: DateTime(2026, 10, 22),
      pricingMode: mode,
      totalPrice: total,
      includes: includes,
      estimatedDaysMin: dMin,
      estimatedDaysMax: dMax,
      validUntil: validUntil,
      isExpired: expired,
    );

const _options = [
  ProposalIncludeOption(slug: 'material', label: 'Material'),
  ProposalIncludeOption(slug: 'waste_removal', label: 'Remoção de resíduos'),
  ProposalIncludeOption(slug: 'travel', label: 'Deslocação'),
];

void main() {
  group('formato do preço (A6)', () {
    test('ProposalPricingMode lê e escreve os valores da BD', () {
      expect(ProposalPricingMode.fromString('fixed_total'),
          ProposalPricingMode.fixedTotal);
      expect(ProposalPricingMode.fromString(null), ProposalPricingMode.hourly);
      expect(ProposalPricingMode.fixedTotal.value, 'fixed_total');
    });

    test('JobProposal.fromJson com e sem as colunas novas', () {
      final base = {
        'id': 'p',
        'job_id': 'j',
        'worker_id': 'w',
        'hourly_rate': 10.71,
        'people_needed': 1,
        'status': 'pending',
        'created_at': '2026-10-22T10:00:00Z',
      };
      final old = JobProposal.fromJson(base);
      expect(old.isFixedTotal, isFalse);
      expect(old.includes, isEmpty);
      expect(old.isExpired, isFalse);

      final fixed = JobProposal.fromJson({
        ...base,
        'pricing_mode': 'fixed_total',
        'total_price': 450,
        'includes': ['material', 'travel'],
        'estimated_days_min': 2,
        'estimated_days_max': 3,
        'valid_until': '2026-11-06',
        'is_expired': true,
      });
      expect(fixed.isFixedTotal, isTrue);
      expect(fixed.totalPrice, 450);
      expect(fixed.includes, ['material', 'travel']);
      expect(fixed.estimatedDaysMax, 3);
      expect(fixed.validUntil, DateTime(2026, 11, 6));
      expect(fixed.isExpired, isTrue);
    });

    test('valor, tipo e total nos dois formatos', () {
      final hourly = _p();
      expect(proposalValueLabel(hourly), '25 €/h');
      expect(proposalPriceKindLabel(hourly), 'preço por hora');
      expect(proposalTotalLabel(hourly), 'cerca de 100 a 150 €');
      expect(proposalTotalNoteLabel(hourly),
          'Estimado. Depende das horas feitas.');

      final fixed = _p(mode: ProposalPricingMode.fixedTotal, total: 450);
      expect(proposalValueLabel(fixed), '450 €');
      expect(proposalPriceKindLabel(fixed), 'valor fechado');
      expect(proposalTotalLabel(fixed), '450 €');
      expect(acceptedProposalPriceLabel(fixed), '450 € · valor fechado');
    });

    test('duração em horas e em dias', () {
      expect(proposalDurationLabel(_p()), '4 a 6 h');
      expect(proposalDurationLabel(_p(hMax: null)), '4 h ou mais');
      expect(proposalDurationLabel(_p(dMin: 2, dMax: 3)), '2 a 3 dias');
      expect(proposalDurationLabel(_p(dMin: 1, dMax: 1)), '1 dia');
      expect(proposalDurationLabel(_p(dMin: 8)), 'mais de 7 dias');
    });

    test('inclui pela ordem das opções', () {
      final p = _p(includes: ['travel', 'material', 'gone']);
      expect(proposalIncludeLabels(p, _options), ['Material', 'Deslocação']);
      expect(proposalIncludesSummaryLabel(p, _options), 'Material, deslocação');
      expect(proposalIncludesSummaryLabel(_p(), _options), isNull);
    });

    test('validade: expira hoje, amanhã, depois e já expirada', () {
      final now = DateTime(2026, 10, 22, 15);
      expect(proposalValidUntilLabel(_p(validUntil: DateTime(2026, 11, 6))),
          'Válido até 06/11');
      expect(
          proposalExpiringSoonLabel(_p(validUntil: DateTime(2026, 10, 22)),
              now: now),
          'hoje, 23:59');
      expect(
          proposalExpiringSoonLabel(_p(validUntil: DateTime(2026, 10, 23)),
              now: now),
          'amanhã, 23:59');
      expect(
          proposalExpiringSoonLabel(_p(validUntil: DateTime(2026, 10, 30)),
              now: now),
          isNull);
      expect(
          proposalExpiringSoonLabel(
              _p(validUntil: DateTime(2026, 10, 22), expired: true),
              now: now),
          isNull);
      expect(proposalExpiredLabel(_p(validUntil: DateTime(2026, 11, 6))),
          'Este orçamento expirou a 06/11');
    });
  });

  group('trabalho em vários dias', () {
    test('quando é em vários dias', () {
      expect(isMultiDayWork(_p()), isFalse);
      expect(isMultiDayWork(_p(dMin: 1, dMax: 1)), isFalse);
      expect(isMultiDayWork(_p(dMin: 2, dMax: 3)), isTrue);
      expect(isMultiDayWork(_p(dMin: 8)), isTrue);
      expect(isMultiDayWork(_p(), dayCount: 2), isTrue);
    });

    test('cabeçalho do dia', () {
      expect(workDayHeaderLabel(1, 3), 'Dia 1 de 3');
      expect(workDayHeaderLabel(4, 3), 'Dia 4 · além dos 3 previstos');
      expect(workDayHeaderLabel(2, null), 'Dia 2');
    });

    test('tempo registado soma os dias, o aberto conta até agora', () {
      final days = [
        JobWorkDay(
          dayNumber: 1,
          startedAt: DateTime(2026, 10, 20, 9),
          endedAt: DateTime(2026, 10, 20, 17, 10),
        ),
        JobWorkDay(dayNumber: 2, startedAt: DateTime(2026, 10, 21, 9)),
      ];
      final total = workedDuration(days, now: DateTime(2026, 10, 21, 18, 30));
      expect(workedTimeLabel(total), '17 h 40 min');
      expect(workedTimeLabel(const Duration(minutes: 45)), '45 min');
      expect(workedTimeLabel(const Duration(hours: 3)), '3 h');
      expect(days.last.isOpen, isTrue);
    });

    test('JobWorkDay.fromJson', () {
      final d = JobWorkDay.fromJson({
        'day_number': 2,
        'started_at': '2026-10-21T09:00:00Z',
        'ended_at': null,
      });
      expect(d.dayNumber, 2);
      expect(d.isOpen, isTrue);
    });
  });

  test('"Os meus trabalhos" mostra o valor fechado', () {
    final e = WorkerJobBoardEntry.fromJson({
      'entry_id': 'e',
      'role': 'responsible',
      'job_id': 'j',
      'hourly_rate': 10.71,
      'estimated_hours_min': 2,
      'estimated_hours_max': 4,
      'status': 'pending',
      'created_at': '2026-10-20T10:00:00Z',
      'job_status': 'open',
      'pricing_mode': 'fixed_total',
      'total_price': 450,
    });
    expect(e.pricingMode, ProposalPricingMode.fixedTotal);
    final text = workerJobCardText(
      e,
      view.WorkerJobsTab.pending,
      DateTime(2026, 10, 22),
    );
    expect(text.amount, '450 €');
    expect(boardFixedPriceLabel(ProposalPricingMode.hourly, 450), isNull);
  });
}
