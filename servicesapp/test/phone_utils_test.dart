import 'package:flutter_test/flutter_test.dart';

import 'package:servicesapp/core/utils/phone_utils.dart';

void main() {
  group('whatsAppNumber', () {
    test('telemóvel português sem indicativo ganha 351', () {
      expect(whatsAppNumber('912345678'), '351912345678');
      expect(whatsAppNumber('912 345 678'), '351912345678');
      expect(whatsAppNumber('912-345-678'), '351912345678');
    });

    test('com +351 ou 00351', () {
      expect(whatsAppNumber('+351 912 345 678'), '351912345678');
      expect(whatsAppNumber('00351912345678'), '351912345678');
      expect(whatsAppNumber('351912345678'), '351912345678');
    });

    test('fixo português', () {
      expect(whatsAppNumber('213 456 789'), '351213456789');
    });

    test('estrangeiro com indicativo', () {
      expect(whatsAppNumber('+34 612 345 678'), '34612345678');
      expect(whatsAppNumber('0044 7911 123456'), '447911123456');
    });

    test('inválidos', () {
      expect(whatsAppNumber('1'), isNull);
      expect(whatsAppNumber('12345678'), isNull);
      expect(whatsAppNumber('812345678'), isNull);
      expect(whatsAppNumber('+351 91234'), isNull);
      expect(whatsAppNumber('91234567a'), isNull);
      expect(whatsAppNumber(''), isNull);
    });
  });

  group('phoneValidator', () {
    test('vazio usa a mensagem dada', () {
      expect(phoneValidator('  ', emptyMessage: 'x'), 'x');
    });

    test('inválido', () {
      expect(phoneValidator('1'), invalidPhoneMessage);
    });

    test('válido', () {
      expect(phoneValidator('912 345 678'), isNull);
    });
  });

  test('whatsAppUri', () {
    expect(
      whatsAppUri('912345678').toString(),
      'https://wa.me/351912345678',
    );
    expect(whatsAppUri('1'), isNull);
  });

  group('phoneForStorage', () {
    test('português fica +351 e só dígitos', () {
      expect(phoneForStorage('912 345 678'), '+351912345678');
      expect(phoneForStorage('00351 912-345-678'), '+351912345678');
      expect(phoneForStorage('+351 912 345 678'), '+351912345678');
      expect(phoneForStorage('351912345678'), '+351912345678');
      expect(phoneForStorage('253 123 456'), '+351253123456');
    });

    test('estrangeiro fica +<dígitos>', () {
      expect(phoneForStorage('+44 20 7946 0958'), '+442079460958');
      expect(phoneForStorage('0033 6 12 34 56 78'), '+33612345678');
    });

    test('inválido fica como foi escrito (sem espaços nas pontas)', () {
      expect(phoneForStorage('  abc  '), 'abc');
    });
  });
}
