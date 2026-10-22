import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/router/app_back_navigation.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/features/admin/application/admin_labels.dart';
import 'package:servicesapp/features/admin/data/admin_models.dart';
import 'package:servicesapp/features/worker/application/worker_plan_labels.dart';
import 'package:servicesapp/features/worker/data/worker_plan_model.dart';

void main() {
  group('WorkerPlanTier', () {
    test('lê os valores da BD e trata desconhecidos como Grátis', () {
      expect(WorkerPlanTier.fromValue('pro'), WorkerPlanTier.pro);
      expect(WorkerPlanTier.fromValue('pro_plus'), WorkerPlanTier.proPlus);
      expect(WorkerPlanTier.fromValue('free'), WorkerPlanTier.free);
      expect(WorkerPlanTier.fromValue(null), WorkerPlanTier.free);
      expect(WorkerPlanTier.fromValue('gold'), WorkerPlanTier.free);
      expect(WorkerPlanTier.proPlus.value, 'pro_plus');
      expect(WorkerPlanTier.proPlus.label, 'Pro+');
    });
  });

  group('plano do jardineiro na conta', () {
    test('Grátis mostra o uso do mês', () {
      final plan = WorkerPlan.fromJson({
        'tier': 'free',
        'ends_at': null,
        'verified': false,
        'jobs_this_month': 3,
        'monthly_job_limit': 5,
      });
      expect(workerPlanSummaryLabel(plan), 'Grátis · 3 de 5 este mês');
      expect(plan.reachedLimit, isFalse);
      expect(workerPlanExplanation(plan), contains('3 de 5'));
    });

    test('Grátis no limite explica quando volta', () {
      const plan = WorkerPlan(
        tier: WorkerPlanTier.free,
        endsAt: null,
        verified: false,
        jobsThisMonth: 5,
        monthlyJobLimit: 5,
      );
      expect(plan.reachedLimit, isTrue);
      expect(workerPlanExplanation(plan), contains('próximo mês'));
    });

    test('Pro com e sem data de fim', () {
      final withEnd = WorkerPlan.fromJson({
        'tier': 'pro',
        'ends_at': '2027-10-22',
        'verified': true,
        'jobs_this_month': 9,
        'monthly_job_limit': null,
      });
      expect(workerPlanSummaryLabel(withEnd), 'Pro · até 22/10/2027');
      expect(withEnd.reachedLimit, isFalse);
      expect(workerPlanExplanation(withEnd), contains('documentos'));
      const noEnd = WorkerPlan(
        tier: WorkerPlanTier.proPlus,
        endsAt: null,
        verified: false,
        jobsThisMonth: 0,
        monthlyJobLimit: null,
      );
      expect(workerPlanSummaryLabel(noEnd), 'Pro+');
    });

    test('sem a migration aplicada não mostra limite', () {
      expect(workerPlanSummaryLabel(WorkerPlan.unavailable), 'Grátis');
      expect(WorkerPlan.unavailable.reachedLimit, isFalse);
    });
  });

  group('textos do painel', () {
    test('percentagens, horas, euros e avaliações', () {
      expect(adminPercentLabel(5, 6), '83%');
      expect(adminPercentLabel(0, 0), '—');
      expect(adminHoursLabel(null), '—');
      expect(adminHoursLabel(3.5), '3,5 h');
      expect(adminRatingLabel(4.75), '4,8');
      expect(adminRatingLabel(null), '—');
      expect(adminEuroLabel(450), contains('450'));
    });

    test('datas relativas', () {
      final now = DateTime(2026, 10, 22, 12);
      expect(adminRelativeDateLabel(null, now: now), 'nunca');
      expect(adminRelativeDateLabel(DateTime(2026, 10, 22, 8), now: now), 'hoje');
      expect(adminRelativeDateLabel(DateTime(2026, 10, 21), now: now), 'ontem');
      expect(adminRelativeDateLabel(DateTime(2026, 10, 12), now: now), 'há 10 dias');
      expect(adminRelativeDateLabel(DateTime(2026, 6, 1), now: now), 'há 4 meses');
    });

    test('meses e tons do plano', () {
      expect(adminMonthShortLabel('2026-10'), 'out');
      expect(adminMonthShortLabel('x'), 'x');
      expect(adminTierStatusColor(WorkerPlanTier.free), AppStatusColor.neutral);
      expect(adminTierStatusColor(WorkerPlanTier.pro), AppStatusColor.success);
    });

    test('voltar dentro do painel cai na entrada do painel', () {
      expect(roleHomeRouteFor('/admin/workers/1'), '/admin');
      expect(roleHomeRouteFor('/worker/jobs'), '/worker/home');
      expect(roleHomeRouteFor('/client/jobs'), '/client/home');
    });
  });

  group('respostas das RPCs do painel', () {
    test('ficha do jardineiro com plano, meses e histórico', () {
      final worker = AdminWorkerDetail.fromJson({
        'worker_id': 'w1',
        'full_name': 'Rui',
        'phone': '+351912345678',
        'services': ['Corte de relva'],
        'proposals_sent': 10,
        'proposals_accepted': 4,
        'tracked_hours': 12.5,
        'estimated_revenue': 310,
        'monthly_jobs': [
          {'month': '2026-09', 'count': 1},
          {'month': '2026-10', 'count': 3},
        ],
        'plan': {
          'active_tier': 'free',
          'tier': 'pro',
          'starts_at': '2025-10-01',
          'ends_at': '2026-10-01',
          'verified_at': null,
          'notes': 'Fundador',
        },
        'plan_history': [
          {
            'created_at': '2025-10-01T10:00:00+00:00',
            'details': {'tier': 'pro', 'ends_at': '2026-10-01'},
          },
        ],
      });
      expect(worker.services, ['Corte de relva']);
      expect(worker.monthlyJobs.last.count, 3);
      expect(worker.plan.tier, WorkerPlanTier.pro);
      expect(worker.plan.activeTier, WorkerPlanTier.free);
      expect(worker.planHistory.single.tier, WorkerPlanTier.pro);
      expect(worker.avgRating, isNull);
    });

    test('visão geral com campos em falta fica a zero', () {
      final overview = AdminOverview.fromJson({'jobs_published': 6});
      expect(overview.jobsPublished, 6);
      expect(overview.clientsTotal, 0);
      expect(overview.avgRating, isNull);
    });
  });
}
