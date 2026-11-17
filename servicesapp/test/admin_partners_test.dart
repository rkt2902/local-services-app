import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/features/admin/application/admin_labels.dart';
import 'package:servicesapp/features/admin/application/admin_providers.dart';
import 'package:servicesapp/features/admin/data/admin_account_models.dart';
import 'package:servicesapp/features/admin/data/admin_partner_models.dart';
import 'package:servicesapp/features/admin/data/admin_repository.dart';
import 'package:servicesapp/features/admin/presentation/admin_map_page.dart';
import 'package:servicesapp/features/admin/presentation/admin_partners_page.dart';
import 'package:servicesapp/features/admin/presentation/admin_shell.dart';
import 'package:servicesapp/features/admin/presentation/widgets/admin_partner_editor.dart';
import 'package:servicesapp/features/fleet_card/data/fleet_card_model.dart';
import 'package:servicesapp/features/notifications/data/notification_types.dart';
import 'package:servicesapp/features/partners/data/partner_model.dart';

// Painel de admin (0082): cartões frota, parceiros e zonas do mapa.
// As RPCs (recusas, decisões, contas das zonas) são testadas na BD
// (supabase/tests/audit/90_admin_partners_zones.sql).

Map<String, dynamic> _cardJson({
  String id = 'c1',
  String status = 'pending',
  String plan = 'pro_plus',
  bool latest = true,
  String? message,
}) => {
  'id': id,
  'worker_id': 'w1',
  'worker_name': 'Rui Jardins',
  'location_name': 'Braga',
  'plan': plan,
  'worker_suspended': false,
  'card_number': '1234',
  'holder_name': 'RUI',
  'barcode_value': '998877',
  'status': status,
  'created_at': '2026-11-15T10:00:00Z',
  'reviewed_at': null,
  'review_message': message,
  'attempts': 2,
  'is_latest': latest,
  'total_count': 1,
};

AdminPartner _partner({
  String id = 'p1',
  String status = 'active',
  int covering = 2,
  bool located = true,
  bool visible = true,
  String? validUntil,
  int opened = 0,
}) => AdminPartner.fromJson({
  'id': id,
  'kind': 'fuel_station',
  'name': 'Posto Avenida',
  'brand': 'Marca X',
  'status': status,
  'headline': '10% em combustível',
  'description': null,
  'image_path': null,
  'discount_code': 'PJ10',
  'barcode_value': null,
  'barcode_format': 'code128',
  'qr_value': null,
  'link_url': null,
  'link_label': null,
  'terms': null,
  'valid_until': validUntil,
  'visible_in_app': visible,
  'pro_plus_only': true,
  'sort_order': 5,
  'address': 'Av. Central 1',
  'locality': 'Braga',
  'lat': located ? 41.55 : null,
  'lng': located ? -8.42 : null,
  'notes': null,
  'created_at': '2026-11-16T10:00:00Z',
  'workers_covering': covering,
  'workers_nearby': 1,
  'jobs_nearby': 5,
  'jobs_unanswered': 1,
  'workers_opened_30d': opened,
  'workers_opened_total': opened * 3,
  'workers_copied_30d': opened > 0 ? 1 : 0,
  'workers_link_30d': opened > 0 ? 2 : 0,
  'workers_map_30d': 0,
});

AdminMapZone _zone(
  String cell, {
  String? area,
  int jobs = 0,
  int unanswered = 0,
  int covering = 0,
  int partners = 0,
  double lat = 41.5,
  double? hours,
}) => AdminMapZone(
  cell: cell,
  latMin: lat,
  lngMin: -8.5,
  latMax: lat + 0.09,
  lngMax: -8.38,
  area: area,
  jobs: jobs,
  jobsUnanswered: unanswered,
  workersCovering: covering,
  partners: partners,
  medianHoursFirstProposal: hours,
);

class _FakeRepo implements AdminRepository {
  final approved = <String>[];
  final saved = <AdminPartnerDraft>[];
  List<AdminFleetCardRow> cards = [AdminFleetCardRow.fromJson(_cardJson())];

  @override
  Future<List<AdminFleetCardRow>> fetchFleetCards({
    String? status = 'pending',
    int page = 0,
  }) async => cards;

  @override
  Future<void> approveFleetCard(String cardId) async => approved.add(cardId);

  @override
  Future<List<AdminPartner>> fetchPartners() async => [_partner()];

  @override
  Future<String> savePartner(AdminPartnerDraft draft) async {
    saved.add(draft);
    return draft.id ?? 'novo';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('cartões frota', () {
    test('lê a linha e o estado', () {
      final c = AdminFleetCardRow.fromJson(_cardJson(plan: 'free'));
      expect(c.isPending, isTrue);
      expect(c.planHasBenefit, isFalse);
      expect(c.attempts, 2);
      expect(adminFleetStatus('active').$1, 'Ativo');
      expect(adminFleetStatus('rejected').$2, AppStatusColor.cancelled);
    });

    test('a app do jardineiro lê a mensagem da recusa', () {
      final card = FleetCard.fromJson({
        'id': 'c1',
        'worker_id': 'w1',
        'barcode_value': '1',
        'status': 'rejected',
        'created_at': '2026-11-16T10:00:00Z',
        'review_message': 'O cartão frota é um benefício do plano Pro+.',
      });
      expect(card.reviewMessage, contains('Pro+'));
    });

    Future<void> pumpTile(
      WidgetTester tester,
      AdminFleetCardRow card, {
      List<String>? log,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AdminFleetCardTile(
              card: card,
              onApprove: () => log?.add('aprovar'),
              onReject: () => log?.add('recusar'),
              onOpenWorker: () => log?.add('ficha'),
            ),
          ),
        ),
      ),
    );

    testWidgets('por aprovar: dados, aprovar e recusar', (tester) async {
      final log = <String>[];
      await pumpTile(tester, AdminFleetCardRow.fromJson(_cardJson()), log: log);
      expect(find.text('998877'), findsOneWidget);
      expect(find.text('Pro+'), findsOneWidget);
      expect(find.textContaining('o cartão frota é do Pro+'), findsNothing);
      await tester.tap(find.text('Aprovar'));
      await tester.tap(find.text('Recusar'));
      await tester.tap(find.text('Abrir ficha'));
      expect(log, ['aprovar', 'recusar', 'ficha']);
    });

    testWidgets('plano Grátis avisa', (tester) async {
      await pumpTile(
        tester,
        AdminFleetCardRow.fromJson(_cardJson(plan: 'free')),
      );
      expect(find.textContaining('o cartão frota é do Pro+'), findsOneWidget);
    });

    testWidgets('ativo: só retirar; antigo: sem ações', (tester) async {
      await pumpTile(
        tester,
        AdminFleetCardRow.fromJson(_cardJson(status: 'active')),
      );
      expect(find.text('Retirar'), findsOneWidget);
      expect(find.text('Aprovar'), findsNothing);

      await pumpTile(
        tester,
        AdminFleetCardRow.fromJson(_cardJson(latest: false)),
      );
      expect(find.text('Substituído por um pedido novo'), findsOneWidget);
      expect(find.text('Aprovar'), findsNothing);
      expect(find.text('Recusar'), findsNothing);
    });

    testWidgets('recusar pede motivo; "Outro" pede mensagem', (tester) async {
      _desktop(tester);
      final sent = <(AdminFleetRejectReason, String?)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminFleetRejectDialog(
              card: AdminFleetCardRow.fromJson(_cardJson()),
              onSubmit: (r, m) async => sent.add((r, m)),
            ),
          ),
        ),
      );
      final confirm = find.widgetWithText(FilledButton, 'Recusar');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.tap(find.text('Outro'));
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byType(TextFormField),
        'Cartão de outra pessoa.',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

      await tester.tap(find.text('Dados ilegíveis'));
      await tester.enterText(find.byType(TextFormField), '');
      await tester.pump();
      expect(find.textContaining('Fotografa-o outra vez'), findsOneWidget);
      await tester.tap(confirm);
      await tester.pump();
      expect(sent.single, (AdminFleetRejectReason.unreadable, null));
    });
  });

  group('parceiros', () {
    test('lê a linha e resume o que há perto', () {
      final p = _partner();
      expect(p.status, AdminPartnerStatus.active);
      expect(
        adminPartnerReachLabel(p),
        '2 jardineiros cobrem · 5 pedidos a 10 km em 90 dias (1 sem resposta)',
      );
      expect(
        adminPartnerReachLabel(_partner(covering: 0)),
        startsWith('Nenhum jardineiro cobre'),
      );
    });

    test('sem localização: sem números', () {
      final p = _partner(located: false);
      expect(p.hasLocation, isFalse);
      expect(adminPartnerReachLabel(p), 'Sem localização no mapa');
    });

    test('aparece na app: ativo, visível e dentro da validade', () {
      final today = DateTime(2026, 11, 16);
      expect(_partner().shownInApp(today: today), isTrue);
      expect(_partner(visible: false).shownInApp(today: today), isFalse);
      expect(_partner(status: 'prospect').shownInApp(today: today), isFalse);
      expect(
        _partner(validUntil: '2026-11-16').shownInApp(today: today),
        isTrue,
      );
      expect(
        _partner(validUntil: '2026-11-15').shownInApp(today: today),
        isFalse,
      );
    });

    test('rascunho: vazios vão a null, nome sem espaços', () {
      final d = AdminPartnerDraft(
        name: '  Posto  ',
        status: AdminPartnerStatus.prospect,
        kind: PartnerKind.gardenStore,
        lat: 38.7,
        lng: -27.2,
        brand: ' ',
        discountCode: ' PJ10 ',
        barcodeFormat: PartnerBarcodeFormat.ean13,
        validUntil: DateTime(2027, 1, 5),
      );
      final data = d.toData();
      expect(data['name'], 'Posto');
      expect(data['kind'], 'garden_store');
      expect(data['status'], 'prospect');
      expect(data['brand'], isNull);
      expect(data['headline'], isNull);
      expect(data['discount_code'], 'PJ10');
      expect(data['barcode_value'], isNull);
      expect(data['barcode_format'], 'ean13');
      expect(data['valid_until'], '2027-01-05');
      expect(data['visible_in_app'], isFalse);
      expect(data['pro_plus_only'], isTrue);
      expect(data['lat'], 38.7);
      expect(data['lng'], -27.2);
      const noPlace = AdminPartnerDraft(
        name: 'Loja',
        status: AdminPartnerStatus.active,
      );
      expect(noPlace.toData()['lat'], isNull);
      final again = AdminPartnerDraft.from(_partner());
      expect(again.id, 'p1');
      expect(again.discountCode, 'PJ10');
      expect(again.visibleInApp, isTrue);
      expect(again.withImage('p1/1.jpg').toData()['image_path'], 'p1/1.jpg');
    });

    test('pré-visualização tira os vazios', () {
      const d = AdminPartnerDraft(
        name: 'Loja',
        status: AdminPartnerStatus.active,
        headline: ' ',
        qrValue: 'https://x.pt',
      );
      final p = d.toPreview();
      expect(p.headline, isNull);
      expect(p.locked, isFalse);
      expect(partnerSections(p), [PartnerSection.qr]);
    });

    test('códigos de barras e link como na BD', () {
      expect(adminIsValidEan13('5601234567890'), isFalse);
      expect(adminIsValidEan13('4006381333931'), isTrue);
      expect(adminIsValidEan13('400638133393'), isFalse);
      expect(adminIsValidCode128('PJ-EXEMPLO-0001'), isTrue);
      expect(adminIsValidCode128('Pão'), isFalse);
      expect(adminBarcodeError('', PartnerBarcodeFormat.ean13), isNull);
      expect(adminBarcodeError('123', PartnerBarcodeFormat.ean13), isNotNull);
      expect(adminLinkError('http://x.pt'), isNotNull);
      expect(adminLinkError('https://x.pt'), isNull);
      expect(adminLinkError(''), isNull);
    });

    test('uso na app', () {
      expect(
        adminPartnerUsageLabel(_partner(opened: 4)),
        'Últimos 30 dias: 4 jardineiros abriram · 1 copiou o código · '
        '2 abriram o link (12 jardineiros desde o início)',
      );
      expect(
        adminPartnerUsageLabel(_partner()),
        'Ainda nenhum jardineiro o abriu na app',
      );
      expect(adminPartnerUsageLabel(_partner(visible: false)), isNull);
    });

    test('alertas de validade e texto do aviso', () {
      expect(adminPartnerAlertMessages(AdminPartnerAlerts.none), isEmpty);
      expect(
        adminPartnerAlertMessages(
          AdminPartnerAlerts.fromJson({'ending_soon': 2, 'expired_visible': 1}),
        ),
        [
          '2 parceiros acabam nos próximos 7 dias',
          '1 parceiro passou a validade e já não aparece na app',
        ],
      );
      expect(adminPartnerNoticeDraft(_partner()), (
        'Parceiro novo: Posto Avenida',
        '10% em combustível. Vê os detalhes na tab Parceiros.',
      ));
    });

    test('resumo do que está preenchido', () {
      expect(adminPartnerFilledLabel(_partner()), 'Código');
      expect(adminPartnerHasCodes(_partner()), isTrue);
      expect(
        adminPartnerFilledLabel(
          AdminPartner.fromJson({'id': 'x', 'name': 'Só nome'}),
        ),
        'Só o nome, por agora',
      );
    });

    test('só Portugal (continente e ilhas)', () {
      expect(adminInPortugal(38.72, -9.14), isTrue);
      expect(adminInPortugal(37.74, -25.67), isTrue);
      expect(adminInPortugal(32.65, -16.91), isTrue);
      expect(adminInPortugal(40.42, -3.70), isFalse);
    });

    testWidgets('editor: grava o parceiro que já existe', (tester) async {
      _desktop(tester);
      final repo = _FakeRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(
              body: AdminPartnerEditor(partner: _partner(), showTiles: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alterar Posto Avenida'), findsOneWidget);
      await tester.tap(find.text('Em conversa'));
      await tester.tap(find.text('Gravar'));
      await tester.pumpAndSettle();
      expect(repo.saved.single.id, 'p1');
      expect(repo.saved.single.status, AdminPartnerStatus.prospect);
      expect(repo.saved.single.discountCode, 'PJ10');
      expect(repo.saved.single.lat, 41.55);
    });

    testWidgets('editor: novo grava só com o nome, sem localização', (
      tester,
    ) async {
      _desktop(tester);
      final repo = _FakeRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(
            home: Scaffold(body: AdminPartnerEditor(showTiles: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Gravar');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome'),
        'Loja Verde',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

      // Um EAN-13 errado trava o Gravar até ser corrigido.
      await tester.tap(find.text('EAN-13'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Código de barras (opcional)'),
        '123',
      );
      await tester.pump();
      expect(find.textContaining('13 dígitos'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Código de barras (opcional)'),
        '4006381333931',
      );
      await tester.pump();

      await tester.tap(find.text('Mostrar na tab Parceiros'));
      await tester.pump();
      expect(
        find.text('Só aparece quando o estado for "Parceiro".'),
        findsOneWidget,
      );
      await tester.tap(find.text('Parceiro'));
      await tester.tap(save);
      await tester.pumpAndSettle();
      final d = repo.saved.single;
      expect(d.id, isNull);
      expect(d.name, 'Loja Verde');
      expect(d.lat, isNull);
      expect(d.visibleInApp, isTrue);
      expect(d.status, AdminPartnerStatus.active);
      expect(d.toData()['barcode_value'], '4006381333931');
    });

    testWidgets('editor: "Ver como na app" só mostra o preenchido', (
      tester,
    ) async {
      _desktop(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(_FakeRepo())],
          child: MaterialApp(
            home: Scaffold(
              body: AdminPartnerEditor(partner: _partner(), showTiles: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver como na app'));
      await tester.pumpAndSettle();
      expect(find.text('Código de desconto'), findsOneWidget);
      expect(find.text('PJ10'), findsNWidgets(2)); // campo e app
      expect(find.text('Onde fica'), findsOneWidget);
      expect(find.text('QR da promoção'), findsNothing);
      expect(find.text('Código de barras'), findsNothing);
      expect(find.text('Condições'), findsNothing);
    });

    testWidgets('página: ver os parceiros e aprovar um cartão', (tester) async {
      _desktop(tester);
      final repo = _FakeRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: Scaffold(body: AdminPartnersPage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Posto Avenida'), findsOneWidget);
      expect(find.textContaining('2 jardineiros cobrem'), findsOneWidget);
      expect(find.text('Na app'), findsOneWidget);
      expect(find.text('Códigos só Pro+'), findsOneWidget);
      expect(find.text('Avisar os jardineiros'), findsOneWidget);
      expect(
        find.text('Ainda nenhum jardineiro o abriu na app'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cartões frota'));
      await tester.pumpAndSettle();
      expect(find.text('Rui Jardins'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Aprovar'));
      await tester.pumpAndSettle();
      expect(find.text('Aprovar o cartão de Rui Jardins?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Aprovar').last);
      await tester.pumpAndSettle();
      expect(repo.approved, ['c1']);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('zonas', () {
    test('lê a zona e a mediana', () {
      final z = AdminMapZone.fromJson(const {
        'cell': '1:2',
        'lat_min': 38.7,
        'lng_min': -27.3,
        'lat_max': 38.79,
        'lng_max': -27.18,
        'area': 'Angra',
        'jobs': 4,
        'jobs_unanswered': 1,
        'jobs_completed': 2,
        'median_hours_first_proposal': 3.5,
        'workers_based': 1,
        'workers_covering': 2,
        'partners': 1,
      });
      expect(z.unansweredRate, 0.25);
      expect(z.hasDemand, isTrue);
      expect(adminZoneCoverageTone(z), AppStatusColor.waiting);
      expect(
        adminZoneDetails(z),
        '4 pedidos em 90 dias, 1 sem resposta, 2 concluídos · 1.ª proposta '
        'em ${adminHoursLabel(3.5)} (mediana) · 2 jardineiros cobrem · '
        '1 com base aqui · 1 parceiro',
      );
    });

    test('cores da densidade', () {
      expect(adminZoneCoverageTone(_zone('a')), AppStatusColor.cancelled);
      expect(
        adminZoneCoverageTone(_zone('a', covering: 3)),
        AppStatusColor.success,
      );
    });

    test('resumo e zonas a reforçar por ordem', () {
      final zones = [
        _zone('ok', area: 'Porto', jobs: 5, covering: 8),
        _zone('sem', area: 'Angra', jobs: 3, unanswered: 2, covering: 1),
        _zone('nada', area: 'Ponta', jobs: 1),
        _zone('posto', area: 'Faro', partners: 1),
        _zone('base', area: 'Beja'),
      ];
      expect(
        adminZonesSummary(zones),
        '1 zona com pedidos sem resposta · 2 com procura e ninguém a cobrir '
        '· quadrados de 10 km, 90 dias',
      );
      expect(adminZonesToReinforce(zones).map((z) => z.cell), [
        'sem',
        'nada',
        'posto',
      ]);
      expect(adminZoneChipLabel(zones[1]), 'Angra · 2 sem resposta');
      expect(adminZoneChipLabel(zones[2]), 'Ponta · ninguém cobre');
    });

    testWidgets('camadas novas: zonas, lista a reforçar e parceiro', (
      tester,
    ) async {
      _desktop(tester);
      final zones = [
        _zone('sem', area: 'Angra', jobs: 3, unanswered: 2, covering: 1),
        _zone('ok', area: 'Porto', jobs: 5, covering: 8, lat: 41.1),
      ];
      AdminMapZone? zone;
      AdminPartner? partner;
      Widget view({AdminMapZone? selectedZone}) => MaterialApp(
        home: Scaffold(
          body: AdminMapView(
            points: const [],
            zones: zones,
            partners: [
              _partner(),
              _partner(id: 'p2', located: false),
            ],
            layers: const {
              AdminMapLayer.unanswered,
              AdminMapLayer.density,
              AdminMapLayer.partners,
            },
            selected: null,
            selectedZone: selectedZone,
            onToggle: (_) {},
            onSelect: (_) {},
            onSelectZone: (z) => zone = z,
            onSelectPartner: (p) => partner = p,
            onOpen: (_) {},
            onRefresh: () {},
            showTiles: false,
          ),
        ),
      );
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();
      expect(find.text('Zonas a reforçar'), findsOneWidget);
      expect(find.text('Angra · 2 sem resposta'), findsOneWidget);
      expect(
        find.textContaining('1 zona com pedidos sem resposta'),
        findsOneWidget,
      );
      expect(find.textContaining('1 parceiro'), findsOneWidget);

      await tester.tap(find.text('8'));
      expect(zone?.cell, 'ok');
      await tester.tap(find.byIcon(Icons.local_gas_station_rounded));
      expect(partner?.id, 'p1');

      await tester.pumpWidget(view(selectedZone: zones.first));
      await tester.pumpAndSettle();
      expect(find.text('Zona · Angra (10 km)'), findsOneWidget);
      expect(find.text('Zonas a reforçar'), findsNothing);
    });
  });

  test('secção, ações do registo e aviso ao jardineiro', () {
    expect(
      AdminSection.fromLocation('/admin/parceiros'),
      AdminSection.partners,
    );
    expect(
      adminHistoryActionLabel('fleet_card_revoked'),
      'Cartão frota retirado',
    );
    expect(adminHistoryActionLabel('partner_created'), 'Parceiro adicionado');
    expect(NotificationType.fleetCardReviewed, 'fleet_card_reviewed');
    expect(AdminMapLayer.density.isZone, isTrue);
    expect(AdminMapLayer.partners.isZone, isFalse);
  });
}
