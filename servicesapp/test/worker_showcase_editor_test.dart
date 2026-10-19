import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/worker/presentation/widgets/worker_edit_profile_view.dart';

/// Editor "Destaques e redes" (design U6): adicionar um destaque abre uma
/// folha, e fechar a folha sem adicionar não deixa texto para o "Guardar".
void main() {
  late TextEditingController highlight;
  late List<String> highlights;
  late int added;

  Widget build() {
    TextEditingController c() => TextEditingController();
    String? ok(String? _) => null;
    final data = WorkerProfileEditViewData(
      profileId: 'w1',
      locationSummaryLabel: '',
      locationNeedsDefinition: false,
      radiusKm: 15,
      radiusSummaryLabel: '',
      servicesSummaryLabel: '',
      toolsSummaryLabel: '',
      ratingsSummaryLabel: '',
      showcaseSummaryLabel: '',
      baseLocation: const WorkerBaseLocationViewData(
        manualCoordinatesEnabled: false,
        radiusKm: 15,
      ),
      servicesAndTools: const WorkerServicesToolsViewData(
        selectedServicesCountLabel: '',
        services: [],
        tools: [],
      ),
      showcase: WorkerShowcaseEditViewData(
        highlights: highlights,
        maxHighlights: 5,
        available: true,
      ),
    );
    return MaterialApp(
      home: Scaffold(
        body: WorkerProfileEditScreen(
          dataAsync: AsyncValue.data(data),
          section: WorkerProfileEditSection.showcase,
          onBack: () {},
          onSectionBack: () {},
          onSignOut: () {},
          fullNameController: c(),
          phoneController: c(),
          bioController: c(),
          hourlyRateController: c(),
          onChangePhoto: () {},
          onOpenBaseLocation: () {},
          onOpenServicesAndTools: () {},
          onOpenRatings: () {},
          onSaveOverview: () async => true,
          addressSearchController: c(),
          latitudeController: c(),
          longitudeController: c(),
          onUseGps: () {},
          onSubmitAddressSearch: () {},
          onToggleManualCoordinates: (_) {},
          onRadiusChanged: (_) {},
          onSaveBaseLocation: () async => true,
          serviceSearchController: c(),
          toolInputController: c(),
          onToggleService: (_) {},
          onAddTool: () {},
          onRemoveTool: (_) {},
          onSaveServicesAndTools: () async => true,
          onOpenShowcase: () {},
          highlightInputController: highlight,
          instagramController: c(),
          facebookController: c(),
          websiteController: c(),
          otherLinkController: c(),
          instagramValidator: ok,
          facebookValidator: ok,
          websiteValidator: ok,
          otherLinkValidator: ok,
          onAddHighlight: () {
            added++;
            highlight.clear();
          },
          onRemoveHighlight: (_) {},
          onPreviewPublicProfile: () {},
          onSaveShowcase: () async => true,
        ),
      ),
    );
  }

  setUp(() {
    highlight = TextEditingController();
    highlights = ['10 anos de experiência'];
    added = 0;
  });

  testWidgets('mostra a contagem e as redes', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.text('Adicionar destaque'), findsOneWidget);
    expect(find.text('· 1 de 5'), findsOneWidget);
    expect(find.text('Outro link'), findsOneWidget);
    expect(find.text('Ver como o cliente vê'), findsOneWidget);
  });

  testWidgets('adicionar pela folha chama o ecrã', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar destaque'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextFormField),
      ),
      'Especialista em oliveiras',
    );
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(added, 1);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('destaque repetido não passa', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar destaque'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextFormField),
      ),
      '10 ANOS de experiência',
    );
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(added, 0);
    expect(find.text('Já tens este destaque.'), findsOneWidget);
  });

  testWidgets('fechar sem adicionar limpa o campo', (tester) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar destaque'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextFormField),
      ),
      'Meio escrito',
    );
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(highlight.text, isEmpty);
    expect(added, 0);
  });
}
