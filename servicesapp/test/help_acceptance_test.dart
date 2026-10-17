import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/help_requests/data/help_request_model.dart';

Map<String, dynamic> _row({Object? message = _absent}) => {
      'id': 'a1',
      'help_request_id': 'h1',
      'worker_id': 'w1',
      'status': 'pending',
      'agreed_rate': 0,
      'brought_equipment': true,
      'created_at': '2026-10-17T10:00:00Z',
      'worker_name': 'Ana',
      'worker_avatar_url': null,
      if (message != _absent) 'message': message,
    };

const _absent = Object();

void main() {
  group('HelpAcceptance.fromJson message', () {
    test('lê a mensagem devolvida pela RPC (0047)', () {
      final a = HelpAcceptance.fromJson(_row(message: '  Tenho corta-relva.  '));
      expect(a.message, 'Tenho corta-relva.');
    });

    test('sem coluna (BD ainda sem a 0047) fica null', () {
      expect(HelpAcceptance.fromJson(_row()).message, isNull);
    });

    test('null ou só espaços fica null', () {
      expect(HelpAcceptance.fromJson(_row(message: null)).message, isNull);
      expect(HelpAcceptance.fromJson(_row(message: '   ')).message, isNull);
    });
  });
}
