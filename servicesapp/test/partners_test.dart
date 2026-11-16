import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:servicesapp/core/widgets/app_bottom_navigation.dart';
import 'package:servicesapp/features/partners/data/partner_model.dart';
import 'package:servicesapp/features/partners/presentation/partners_screen.dart';
import 'package:servicesapp/features/partners/presentation/widgets/partner_detail_view.dart';
import 'package:servicesapp/features/worker/presentation/worker_shell.dart';

// Parceiros na app do jardineiro (0082): o ecrã de cada parceiro só mostra
// o que o painel tem preenchido. O que a BD devolve a cada plano (códigos
// escondidos a quem não é Pro+) é testado em
// supabase/tests/audit/90_admin_partners_zones.sql.

Map<String, dynamic> _full = {
  'id': 'p1',
  'kind': 'fuel_station',
  'name': 'Posto Avenida',
  'brand': 'Marca X',
  'headline': '10% em combustível',
  'description': 'Desconto em todos os combustíveis.',
  'image_path': null,
  'discount_code': 'PJ10',
  'barcode_value': 'PJ-0001',
  'barcode_format': 'code128',
  'qr_value': 'https://projardim.pt',
  'link_url': 'https://projardim.pt',
  'link_label': 'Ver o site',
  'terms': 'Não acumula.',
  'valid_until': '2027-01-31',
  'address': 'Av. Central 1',
  'locality': 'Braga',
  'lat': 41.55,
  'lng': -8.42,
  'locked': false,
  'has_discount_code': true,
  'has_barcode': true,
  'has_qr': true,
};

Partner _partner([Map<String, dynamic> changes = const {}]) =>
    Partner.fromJson({..._full, ...changes});

Partner get _minimal => Partner.fromJson({'id': 'p2', 'name': 'Loja Verde'});

Partner get _locked => _partner({
  'locked': true,
  'discount_code': null,
  'barcode_value': null,
  'qr_value': null,
  'has_barcode': false,
});

Future<void> _pumpDetail(WidgetTester tester, Partner p) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PartnerDetailView(
            partner: p,
            showMapTiles: false,
            onCopyCode: (_) {},
            onOpenLink: (_) {},
            onOpenMap: (_, _) {},
            onUnlock: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('modelo', () {
    test('lê tudo e as partes vêm pela ordem', () {
      final p = _partner();
      expect(p.kind, PartnerKind.fuelStation);
      expect(p.validUntil, DateTime(2027, 1, 31));
      expect(p.hasLocation, isTrue);
      expect(partnerSections(p), [
        PartnerSection.description,
        PartnerSection.discountCode,
        PartnerSection.barcode,
        PartnerSection.qr,
        PartnerSection.location,
        PartnerSection.link,
        PartnerSection.terms,
      ]);
    });

    test('em branco não conta; só nome = sem partes', () {
      final p = _partner({
        'description': '  ',
        'terms': '',
        'valid_until': null,
        'link_url': null,
      });
      expect(p.description, isNull);
      expect(partnerSections(p), isNot(contains(PartnerSection.description)));
      expect(partnerSections(p), isNot(contains(PartnerSection.terms)));
      expect(partnerSections(p), isNot(contains(PartnerSection.link)));
      expect(partnerSections(_minimal), isEmpty);
      expect(_minimal.kind, PartnerKind.other);
    });

    test('só morada, sem ponto no mapa, ainda mostra "Onde fica"', () {
      final p = _partner({'lat': null, 'lng': null});
      expect(p.hasLocation, isFalse);
      expect(partnerSections(p), contains(PartnerSection.location));
    });

    test('bloqueado: diz o que o Pro+ desbloqueia', () {
      expect(_locked.lockedPerks, ['código de desconto', 'QR da promoção']);
      expect(partnerSections(_locked).first, PartnerSection.description);
      expect(partnerSections(_locked), contains(PartnerSection.locked));
      expect(
        partnerSections(_locked),
        isNot(contains(PartnerSection.discountCode)),
      );
    });

    test('URL da foto', () {
      expect(
        partnerImageUrl(null, supabaseUrl: 'https://x.supabase.co'),
        isNull,
      );
      expect(
        partnerImageUrl('p1/1.jpg', supabaseUrl: 'https://x.supabase.co/'),
        'https://x.supabase.co/storage/v1/object/public/partner-images/p1/1.jpg',
      );
    });
  });

  group('ecrã do parceiro', () {
    testWidgets('com tudo preenchido mostra cada parte', (tester) async {
      await _pumpDetail(tester, _partner());
      expect(find.text('Posto Avenida'), findsOneWidget);
      expect(find.text('10% em combustível'), findsOneWidget);
      expect(find.text('Código de desconto'), findsOneWidget);
      expect(find.text('PJ10'), findsOneWidget);
      expect(find.byType(BarcodeWidget), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Onde fica'), findsOneWidget);
      expect(find.text('Abrir no mapa'), findsOneWidget);
      expect(find.text('Ver o site'), findsOneWidget);
      expect(find.text('Válido até 31/01/2027'), findsOneWidget);
      expect(find.text('Disponível no Pro+'), findsNothing);
    });

    testWidgets('só com o nome não mostra nenhuma parte', (tester) async {
      await _pumpDetail(tester, _minimal);
      expect(find.text('Loja Verde'), findsOneWidget);
      for (final title in [
        'Código de desconto',
        'Código de barras',
        'QR da promoção',
        'Onde fica',
        'Condições',
        'Abrir o site',
      ]) {
        expect(find.text(title), findsNothing, reason: title);
      }
      expect(find.byType(BarcodeWidget), findsNothing);
      expect(find.byType(QrImageView), findsNothing);
    });

    testWidgets('sem texto do botão usa "Abrir o site"', (tester) async {
      await _pumpDetail(tester, _partner({'link_label': null}));
      expect(find.text('Abrir o site'), findsOneWidget);
    });

    testWidgets('bloqueado: aviso do Pro+ e sem códigos', (tester) async {
      var unlocked = false;
      tester.view.physicalSize = const Size(420, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PartnerDetailView(
                partner: _locked,
                showMapTiles: false,
                onUnlock: () => unlocked = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Disponível no Pro+'), findsOneWidget);
      expect(
        find.textContaining('código de desconto e QR da promoção'),
        findsOneWidget,
      );
      expect(find.byType(QrImageView), findsNothing);
      await tester.tap(find.text('Ver planos'));
      expect(unlocked, isTrue);
    });

    testWidgets('copiar o código', (tester) async {
      String? copied;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PartnerDetailView(
                partner: _partner(),
                showMapTiles: false,
                onCopyCode: (c) => copied = c,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Copiar'));
      await tester.tap(find.text('Copiar'));
      expect(copied, 'PJ10');
    });
  });

  group('lista', () {
    testWidgets('um banner por parceiro; tocar abre', (tester) async {
      Partner? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PartnersList(
              partners: [_partner(), _locked, _minimal],
              onOpen: (p) => opened = p,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Posto Avenida'), findsNWidgets(2));
      expect(find.text('Loja Verde'), findsOneWidget);
      expect(find.text('Pro+'), findsOneWidget);
      await tester.ensureVisible(find.text('Loja Verde'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Loja Verde'));
      expect(opened?.id, 'p2');
    });

    testWidgets('vazia', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PartnersList(partners: const [], onOpen: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ainda sem parceiros'), findsOneWidget);
    });
  });

  group('menu do jardineiro', () {
    test('"Parceiros" só existe com parceiros, antes do Perfil', () {
      final without = workerShellRoutes(showPartners: false);
      final withPartners = workerShellRoutes(showPartners: true);
      expect(without, hasLength(4));
      expect(withPartners, hasLength(5));
      expect(withPartners[3], '/worker/partners');
      expect(withPartners.last, '/worker/profile');
      expect(workerShellIndex('/worker/partners', withPartners), 3);
      expect(workerShellIndex('/worker/profile', withPartners), 4);
      expect(workerShellIndex('/worker/profile', without), 3);
      expect(workerShellIndex('/worker/jobs', withPartners), 2);
      expect(workerShellIndex('/worker/job/1', withPartners), 0);
      // Sem o botão (parceiros desapareceram): volta ao Início.
      expect(workerShellIndex('/worker/partners', without), 0);
    });

    testWidgets('cinco botões cabem num telemóvel pequeno', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      int? selected;
      var central = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavigation(
              selectedIndex: 3,
              onItemSelected: (i) => selected = i,
              onCentralActionPressed: () => central = true,
              items: const [
                AppBottomNavigationItem(
                  label: 'Início',
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                ),
                AppBottomNavigationItem(
                  label: 'Pedidos',
                  icon: Icons.work_outline_rounded,
                  selectedIcon: Icons.work_rounded,
                ),
                AppBottomNavigationItem(
                  label: 'Trabalhos',
                  icon: Icons.event_note_outlined,
                  selectedIcon: Icons.event_note_rounded,
                ),
                AppBottomNavigationItem(
                  label: 'Parceiros',
                  icon: Icons.storefront_outlined,
                  selectedIcon: Icons.storefront_rounded,
                ),
                AppBottomNavigationItem(
                  label: 'Perfil',
                  icon: Icons.person_outline_rounded,
                  selectedIcon: Icons.person_rounded,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Parceiros'), findsOneWidget);
      await tester.tap(find.text('Perfil'));
      expect(selected, 4);
      await tester.tap(find.text('Pedidos'));
      expect(selected, 1);
      await tester.tap(find.byIcon(Icons.add_rounded));
      expect(central, isTrue);
      // O "+" fica entre o segundo e o terceiro botão.
      final plus = tester.getCenter(find.byIcon(Icons.add_rounded)).dx;
      expect(plus, greaterThan(tester.getCenter(find.text('Pedidos')).dx));
      expect(plus, lessThan(tester.getCenter(find.text('Trabalhos')).dx));
    });
  });
}
