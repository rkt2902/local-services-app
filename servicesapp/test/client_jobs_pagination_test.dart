import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/utils/app_status_presenters.dart';
import 'package:servicesapp/features/jobs/application/job_providers.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';
import 'package:servicesapp/features/jobs/presentation/widgets/client_jobs_view.dart';

JobRequest _job(int i) => JobRequest(
      id: 'j$i',
      clientId: 'c1',
      serviceTypeId: 's1',
      addressText: 'Rua A, Braga',
      locationLat: 0,
      locationLng: 0,
      description: 'Cortar a relva',
      status: JobStatus.completed,
      proposalCount: 0,
      dateMode: DateMode.flexible,
      expiresAt: DateTime(2026, 10, 20),
      createdAt: DateTime(2026, 10, 1).add(Duration(days: i)),
    );

ClientJobListItemViewData _item(int i) => ClientJobListItemViewData(
      jobId: 'j$i',
      title: 'Relva $i',
      addressText: 'Rua A, Braga',
      locationLat: 0,
      locationLng: 0,
      dateLabel: 'Flexível',
      serviceIcon: Icons.grass,
      statusPresentation: JobStatus.completed.presentation(),
    );

void main() {
  group('clientHistoryPage', () {
    test('com mais um do que o limite, corta e diz que há mais', () {
      final page = clientHistoryPage([for (var i = 0; i < 21; i++) _job(i)], 20);
      expect(page.visible, hasLength(20));
      expect(page.hasMore, isTrue);
    });

    test('até ao limite, mostra tudo e não há mais', () {
      final page = clientHistoryPage([for (var i = 0; i < 20; i++) _job(i)], 20);
      expect(page.visible, hasLength(20));
      expect(page.hasMore, isFalse);
    });
  });

  testWidgets('Histórico mostra "Ver pedidos mais antigos" quando há mais',
      (tester) async {
    var loads = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: ClientJobsScreen(
          dataAsync: AsyncValue.data(ClientJobsViewData(
            activeJobs: const [],
            historyJobs: [_item(1)],
            hasMoreHistory: true,
          )),
          onOpenJob: (_) {},
          onCreateJob: () {},
          onLoadMoreHistory: () => loads++,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ver pedidos mais antigos'), findsNothing);
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver pedidos mais antigos'));
    expect(loads, 1);
  });
}
