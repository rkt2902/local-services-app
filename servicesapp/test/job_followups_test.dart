import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/constants/enums.dart';
import 'package:servicesapp/core/theme/app_status_color.dart';
import 'package:servicesapp/features/client/presentation/widgets/client_edit_profile_view.dart';
import 'package:servicesapp/features/client/presentation/widgets/no_proposals_help_card.dart';
import 'package:servicesapp/features/jobs/application/no_proposals_labels.dart';
import 'package:servicesapp/features/jobs/data/job_model.dart';
import 'package:servicesapp/features/notifications/application/notification_presentation.dart';
import 'package:servicesapp/features/notifications/data/notification_types.dart';

// Pedido sem propostas (RC5), lembretes e dicas da época (migration 0062).

JobRequest _job({
  JobStatus status = JobStatus.open,
  int proposals = 0,
  int extraKm = 10,
  DateTime? nudgedAt,
  DirectRequestStatus? direct,
}) => JobRequest(
  id: 'job-1',
  clientId: 'client',
  serviceTypeId: 'relva',
  addressText: 'Rua das Flores 12, Braga',
  locationLat: 41.55,
  locationLng: -8.42,
  description: 'Relva das traseiras.',
  status: status,
  proposalCount: proposals,
  expiresAt: DateTime(2026, 12, 1),
  createdAt: DateTime(2026, 10, 1),
  directWorkerId: direct == null ? null : 'rui',
  directUntil: direct == null ? null : DateTime(2099),
  directStatus: direct,
  searchExtraKm: extraKm,
  noProposalsNudgedAt: nudgedAt,
);

final _nudged = DateTime(2026, 10, 23, 10);

NoProposalsHelpCardViewData _cardData({String? widen = 'Mostrar mais longe'}) =>
    NoProposalsHelpCardViewData(
      titleLabel: 'Ainda sem propostas',
      descriptionLabel: 'Uma data mais flexível ajuda.',
      dateActionLabel: noProposalsDateActionLabel,
      descriptionActionLabel: noProposalsDescriptionActionLabel,
      widenActionLabel: widen,
    );

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('cartão "Ainda sem propostas"', () {
    test('só depois do aviso das 24h, aberto e sem propostas', () {
      expect(noProposalsHelpTexts(_job()), isNull);
      expect(noProposalsHelpTexts(_job(nudgedAt: _nudged)), isNotNull);
      expect(
        noProposalsHelpTexts(_job(nudgedAt: _nudged, proposals: 1)),
        isNull,
      );
      expect(
        noProposalsHelpTexts(
          _job(nudgedAt: _nudged, status: JobStatus.confirmed),
        ),
        isNull,
      );
      expect(
        noProposalsHelpTexts(
          _job(nudgedAt: _nudged, direct: DirectRequestStatus.waiting),
        ),
        isNull,
      );
    });

    test('diz até onde já foi e esconde o botão no máximo', () {
      final texts = noProposalsHelpTexts(_job(nudgedAt: _nudged))!;
      expect(texts.title, 'Ainda sem propostas');
      expect(texts.description, contains('até 10 km mais longe'));
      expect(texts.widenActionLabel, 'Mostrar a jardineiros mais longe');

      final none = noProposalsHelpTexts(_job(nudgedAt: _nudged, extraKm: 0))!;
      expect(none.description, isNot(contains('km')));

      final max = noProposalsHelpTexts(
        _job(nudgedAt: _nudged, extraKm: JobRequest.maxSearchExtraKm),
      )!;
      expect(max.widenActionLabel, isNull);
    });

    test('aviso depois de alargar', () {
      expect(
        widenedSearchToast(20),
        'Pedido mostrado a jardineiros até 20 km mais longe.',
      );
    });

    testWidgets('editar e alargar chamam o ecrã; erro fica no cartão', (
      tester,
    ) async {
      var edits = 0;
      var widens = 0;
      await tester.pumpWidget(
        _app(
          NoProposalsHelpCard(
            data: _cardData(),
            onEditRequest: () => edits++,
            onWiden: () async {
              widens++;
              return 'Este pedido já não está aberto.';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(noProposalsDateActionLabel));
      await tester.tap(find.text(noProposalsDescriptionActionLabel));
      expect(edits, 2);

      await tester.tap(find.text('Mostrar mais longe'));
      await tester.pumpAndSettle();
      expect(widens, 1);
      expect(find.text('Este pedido já não está aberto.'), findsOneWidget);
    });

    testWidgets('sem botão de alargar no máximo', (tester) async {
      await tester.pumpWidget(
        _app(
          NoProposalsHelpCard(
            data: _cardData(widen: null),
            onEditRequest: () {},
            onWiden: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mostrar mais longe'), findsNothing);
      expect(find.text(noProposalsDateActionLabel), findsOneWidget);
    });
  });

  group('dados', () {
    test('JobRequest lê o alcance e o aviso', () {
      final job = JobRequest.fromJson({
        'id': 'j',
        'client_id': 'c',
        'service_type_id': 's',
        'location_lat': 1,
        'location_lng': 2,
        'description': 'd',
        'status': 'open',
        'expires_at': '2026-10-24T10:00:00Z',
        'created_at': '2026-10-22T10:00:00Z',
        'search_extra_km': 20,
        'no_proposals_nudged_at': '2026-10-23T10:00:00Z',
      });
      expect(job.searchExtraKm, 20);
      expect(job.noProposalsNudgedAt, DateTime.utc(2026, 10, 23, 10));

      final old = JobRequest.fromJson({
        'id': 'j',
        'client_id': 'c',
        'service_type_id': 's',
        'location_lat': 1,
        'location_lng': 2,
        'description': 'd',
        'status': 'open',
        'expires_at': '2026-10-24T10:00:00Z',
        'created_at': '2026-10-22T10:00:00Z',
      });
      expect(old.searchExtraKm, 0);
      expect(old.noProposalsNudgedAt, isNull);
      expect(old.copyWith(description: 'x').searchExtraKm, 0);
    });
  });

  group('notificações novas', () {
    test('ícone e tom próprios', () {
      expect(
        notificationLook(NotificationType.jobOpportunityReminder).tone,
        AppStatusColor.waiting,
      );
      expect(
        notificationLook(NotificationType.jobNoProposalsYet).icon,
        Icons.travel_explore_rounded,
      );
      expect(
        notificationLook(NotificationType.seasonalTip).icon,
        Icons.eco_outlined,
      );
    });

    test('lembretes e dicas ficam fora de "Trabalhos"', () {
      expect(
        isJobNotification(NotificationType.jobOpportunityReminder),
        isFalse,
      );
      expect(isJobNotification(NotificationType.seasonalTip), isFalse);
      expect(isJobNotification(NotificationType.jobNoProposalsYet), isTrue);
    });
  });

  group('dicas da época', () {
    testWidgets('o interruptor muda logo', (tester) async {
      bool? changed;
      await tester.pumpWidget(
        _app(SeasonalTipsSwitch(value: true, onChanged: (v) => changed = v)),
      );
      expect(find.text('Dicas da época'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      expect(changed, isFalse);
    });
  });
}
