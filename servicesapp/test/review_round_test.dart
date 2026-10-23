import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/services/geocoding_service.dart';
import 'package:servicesapp/core/widgets/address_suggestions_list.dart';
import 'package:servicesapp/features/client/presentation/client_create_job_schedule_screen.dart';
import 'package:servicesapp/features/jobs/application/direct_request_labels.dart';
import 'package:servicesapp/features/jobs/data/direct_request_models.dart';
import 'package:servicesapp/features/worker/presentation/worker_setup_screen.dart';

// Revisão de 23/10: preço do trabalho anterior, foto do jardineiro, pesquisa
// de morada e campos em falta no passo 2 do pedido.

void main() {
  group('"Já trabalhaste com..." (0063)', () {
    test('valor fechado aparece como total, não como taxa', () {
      final ctx = DirectRequestContext.fromJson({
        'client_name': 'Marta Silva',
        'job_date': '2026-09-12',
        'service_type_id': 's',
        'hourly_rate': 62.5,
        'pricing_mode': 'fixed_total',
        'total_price': 1000,
      });
      expect(ctx.totalPrice, 1000);
      final label = directHistoryLabel(ctx, serviceLabel: 'Corte de relva');
      expect(label, contains('1000 € no total'));
      expect(label, isNot(contains('/h')));
    });

    test('por hora (ou RPC antiga) continua com a taxa', () {
      final ctx = DirectRequestContext.fromJson({
        'client_name': 'Marta',
        'job_date': null,
        'service_type_id': 's',
        'hourly_rate': 12,
      });
      expect(ctx.totalPrice, isNull);
      expect(directHistoryLabel(ctx, serviceLabel: ''), contains('€/h'));
    });
  });

  group('registo do jardineiro', () {
    test('diz o que falta', () {
      expect(
        workerSetupMissingLabel(
          hasPhoto: false,
          hasServices: false,
          hasArea: false,
        ),
        'Falta a foto, os serviços e a zona de trabalho.',
      );
      expect(
        workerSetupMissingLabel(
          hasPhoto: false,
          hasServices: true,
          hasArea: true,
        ),
        'Falta a foto.',
      );
      expect(
        workerSetupMissingLabel(
          hasPhoto: true,
          hasServices: true,
          hasArea: true,
        ),
        '',
      );
    });

    test('a foto da conta Google conta', () {
      expect(
        workerSetupPhotoHint(hasPhoto: true, fromSocialAccount: true),
        contains('foto da tua conta'),
      );
      expect(
        workerSetupPhotoHint(hasPhoto: false, fromSocialAccount: false),
        startsWith('Foto obrigatória'),
      );
    });
  });

  group('passo 2 do pedido', () {
    test('diz o que falta, a dimensão incluída', () {
      expect(
        createJobScheduleMissingLabel(
          hasDate: true,
          hasLocation: true,
          hasSize: false,
        ),
        'Falta escolher a dimensão do espaço.',
      );
      expect(
        createJobScheduleMissingLabel(
          hasDate: false,
          hasLocation: false,
          hasSize: false,
        ),
        'Falta escolher a data, o local no mapa e a dimensão do espaço.',
      );
      expect(
        createJobScheduleMissingLabel(
          hasDate: true,
          hasLocation: true,
          hasSize: true,
        ),
        isNull,
      );
    });
  });

  group('pesquisa de morada', () {
    test('Photon: rua, número, código postal e localidade; fora de PT não', () {
      final list = parsePhotonSuggestions({
        'features': [
          {
            'geometry': {
              'coordinates': [-8.51, 41.70],
            },
            'properties': {
              'street': 'Avenida do Carreiro',
              'housenumber': '1',
              'postcode': '4730-424',
              'city': 'Vila Verde',
              'countrycode': 'PT',
            },
          },
          {
            'geometry': {
              'coordinates': [-8.51, 41.70],
            },
            'properties': {
              'street': 'Avenida do Carreiro',
              'housenumber': '1',
              'postcode': '4730-424',
              'city': 'Vila Verde',
              'countrycode': 'PT',
            },
          },
          {
            'geometry': {
              'coordinates': [-8.0, 42.3],
            },
            'properties': {'name': 'Ourense', 'countrycode': 'ES'},
          },
          {
            'geometry': {
              'coordinates': [-8.42, 41.55],
            },
            'properties': {
              'name': 'Braga',
              'city': 'Braga',
              'countrycode': 'PT',
            },
          },
        ],
      });
      expect(list, hasLength(2));
      expect(list.first.title, 'Avenida do Carreiro 1');
      expect(list.first.subtitle, '4730-424 Vila Verde');
      expect(list.first.fullText, 'Avenida do Carreiro 1, 4730-424 Vila Verde');
      expect(list.first.lat, 41.70);
      expect(list.first.locality, 'Vila Verde');
      expect(list.last.fullText, 'Braga');
    });

    test('Nominatim com addressdetails', () {
      final list = parseNominatimSuggestions([
        {
          'lat': '41.69',
          'lon': '-8.50',
          'display_name': 'x',
          'address': {
            'road': 'Rua das Flores',
            'house_number': '23',
            'postcode': '4730-423',
            'town': 'Vila Verde',
          },
        },
      ]);
      expect(list.single.title, 'Rua das Flores 23');
      expect(list.single.subtitle, '4730-423 Vila Verde');
    });

    testWidgets('tocar numa sugestão escolhe-a; sem nada mostra a dica', (
      tester,
    ) async {
      AddressSuggestion? picked;
      const s = AddressSuggestion(
        title: 'Rua das Flores 23',
        subtitle: 'Vila Verde',
        lat: 41.69,
        lng: -8.5,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressSuggestionsList(
              suggestions: const [s],
              loading: false,
              onSelected: (v) => picked = v,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rua das Flores 23'));
      expect(picked, same(s));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AddressSuggestionsList(
              suggestions: [],
              loading: false,
              onSelected: _ignore,
              emptyHint: addressNotFoundHint,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(addressNotFoundHint), findsOneWidget);
    });
  });
}

void _ignore(AddressSuggestion _) {}
