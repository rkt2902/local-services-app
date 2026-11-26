import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:servicesapp/features/admin/data/admin_partner_stats_models.dart';
import 'package:servicesapp/features/worker/application/fuel_usage_providers.dart';
import 'package:servicesapp/features/worker/data/fuel_usage_model.dart';
import 'package:servicesapp/features/worker/data/fuel_usage_repository.dart';
import 'package:servicesapp/features/worker/presentation/worker_fuel_usage_screen.dart';

class _FakeRepo implements FuelUsageRepository {
  final saves = <List<FuelUsageEntry>>[];

  @override
  Future<void> saveMyUsage(List<FuelUsageEntry> entries) async =>
      saves.add(entries);

  @override
  Future<List<FuelType>> fetchFuelTypes() async => _types;

  @override
  Future<List<FuelUsageEntry>> fetchMyUsage() async => const [];
}

const _types = [
  FuelType(id: 'diesel', name: 'Gasóleo'),
  FuelType(id: 'petrol', name: 'Gasolina'),
  FuelType(id: 'oil_2t', name: 'Óleo 2 tempos', isOil: true),
];

Future<_FakeRepo> _pump(
  WidgetTester tester, {
  List<FuelUsageEntry> saved = const [],
  FuelUsageScreenMode mode = FuelUsageScreenMode.onboarding,
}) async {
  final repo = _FakeRepo();
  final router = GoRouter(
    initialLocation: '/fuel',
    routes: [
      GoRoute(path: '/worker/home', builder: (_, _) => const Text('INÍCIO')),
      GoRoute(
          path: '/fuel', builder: (_, _) => WorkerFuelUsageScreen(mode: mode)),
    ],
  );
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      fuelUsageRepositoryProvider.overrideWithValue(repo),
      fuelTypesProvider.overrideWith((ref) async => _types),
      myFuelUsageProvider.overrideWith((ref) async => saved),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('registo: abre com uma linha vazia e pode saltar',
      (tester) async {
    final repo = await _pump(tester);
    expect(find.text('Combustível 1'), findsOneWidget);
    expect(find.byTooltip('Remover combustível 1'), findsNothing);
    expect(find.text('Opcional. Pode preencher mais tarde no Perfil.'),
        findsOneWidget);
    await tester.tap(find.text('Saltar por agora'));
    await tester.pumpAndSettle();
    expect(find.text('INÍCIO'), findsOneWidget);
    expect(repo.saves, isEmpty);
  });

  testWidgets('combustível sem litros bloqueia; com litros grava e entra',
      (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('Gasolina'));
    await tester.pump();
    expect(find.text('Faltam os litros de Gasolina.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '80');
    await tester.pump();
    expect(find.text('Faltam os litros de Gasolina.'), findsNothing);

    // Segunda linha: a Gasolina já está escolhida na primeira.
    await tester.ensureVisible(find.text('Adicionar outro combustível'));
    await tester.tap(find.text('Adicionar outro combustível'));
    await tester.pumpAndSettle();
    expect(find.text('Combustível 2'), findsOneWidget);
    expect(find.byTooltip('Remover combustível 2'), findsOneWidget);
    await tester.ensureVisible(find.text('Óleo 2 tempos').last);
    await tester.tap(find.text('Óleo 2 tempos').last);
    await tester.enterText(find.byType(TextField).last, '4,5');
    await tester.pump();

    await tester.tap(find.text('Entrar na app'));
    await tester.pumpAndSettle();
    expect(find.text('INÍCIO'), findsOneWidget);
    expect(repo.saves.single.map((e) => e.toJson()).toList(), [
      {'fuel_type_id': 'petrol', 'liters_per_month': 80.0},
      {'fuel_type_id': 'oil_2t', 'liters_per_month': 4.5},
    ]);
  });

  testWidgets('remover uma linha', (tester) async {
    await _pump(tester, saved: const [
      FuelUsageEntry(fuelTypeId: 'diesel', litersPerMonth: 120),
      FuelUsageEntry(fuelTypeId: 'oil_2t', litersPerMonth: 2),
    ], mode: FuelUsageScreenMode.profile);
    expect(find.text('Combustível 2'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Saltar por agora'), findsNothing);
    await tester.tap(find.byTooltip('Remover combustível 2'));
    await tester.pumpAndSettle();
    expect(find.text('Combustível 2'), findsNothing);
    expect(find.text('120'), findsOneWidget);
  });

  test('estatísticas: meses sem trabalhos e estimativa', () {
    final s = AdminPartnerStats.fromJson({
      'months': 3,
      'workers': {'registered': 10, 'active_30d': 4, 'pro': 2, 'pro_plus': 1},
      'survey': {'answered': 4},
      'fuel': [
        {'id': 'diesel', 'name': 'Gasóleo', 'workers': 3, 'liters': 300},
        {'id': 'oil_2t', 'name': 'Óleo 2 tempos', 'workers': 2, 'liters': 10},
      ],
      'districts': [
        {
          'district': 'Braga', 'registered': 6, 'active_30d': 3,
          'answered': 2, 'liters': {'diesel': 200},
        },
      ],
      'completed': [
        {'month': '2026-11', 'category': 'Jardinagem', 'count': 5},
        {'month': '2026-11', 'category': 'Floresta', 'count': 2},
      ],
    }, now: DateTime(2026, 11, 26));
    expect(s.completed.map((m) => '${m.month}=${m.total}').toList(),
        ['2026-09=0', '2026-10=0', '2026-11=7']);
    expect(s.totalLiters, 310);
    expect(s.estimatedLitersAll, 775);
    expect(adminLitersLabel(12345.4), '12 345 L');
    expect(adminPercent(4, 10), '40%');
    expect(adminPercent(1, 0), '—');
    expect(adminMonthLabel('2026-01'), 'jan 2026');
  });
}
