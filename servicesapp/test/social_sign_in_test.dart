import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/auth/application/pending_signup_provider.dart';
import 'package:servicesapp/features/auth/data/auth_repository.dart';
import 'package:servicesapp/features/auth/presentation/choose_role_screen.dart';
import 'package:servicesapp/features/auth/presentation/widgets/social_sign_in_buttons.dart';

void main() {
  group('RegistrationIdentity', () {
    test('registo por email: usa o que foi escrito, sem pedir contacto', () {
      final identity = RegistrationIdentity.from(
        pending: const PendingSignupState(
          fullName: 'Ana Silva',
          phone: '912345678',
        ),
        metadata: const {'full_name': 'Outro', 'phone': '931111111'},
      );
      expect(identity.fullName, 'Ana Silva');
      expect(identity.phone, '912345678');
      expect(identity.socialAvatarUrl, isNull);
      expect(identity.needsContact, isFalse);
    });

    test('app fechada a meio da confirmação: lê os metadados do signUp', () {
      final identity = RegistrationIdentity.from(
        pending: const PendingSignupState(),
        metadata: const {'full_name': 'Ana Silva', 'phone': '912345678'},
      );
      expect(identity.fullName, 'Ana Silva');
      expect(identity.needsContact, isFalse);
    });

    test('Google: nome e foto da conta, telemóvel por pedir', () {
      final identity = RegistrationIdentity.from(
        pending: const PendingSignupState(),
        metadata: const {
          'full_name': 'Rui Costa',
          'name': 'Rui Costa',
          'avatar_url': 'https://lh3.googleusercontent.com/a/abc=s96-c',
          'picture': 'https://lh3.googleusercontent.com/a/abc=s96-c',
          'email': 'rui@example.com',
        },
      );
      expect(identity.fullName, 'Rui Costa');
      expect(identity.phone, '');
      expect(identity.needsContact, isTrue);
      expect(identity.socialAvatarUrl,
          'https://lh3.googleusercontent.com/a/abc=s96-c');
    });

    test('Facebook só com name e picture', () {
      final identity = RegistrationIdentity.from(
        pending: const PendingSignupState(),
        metadata: const {
          'name': 'Marta Reis',
          'picture': 'https://graph.facebook.com/1/picture?type=large',
        },
      );
      expect(identity.fullName, 'Marta Reis');
      expect(identity.socialAvatarUrl,
          'https://graph.facebook.com/1/picture?type=large');
    });

    test('sem metadados', () {
      final identity = RegistrationIdentity.from(
        pending: const PendingSignupState(),
        metadata: null,
      );
      expect(identity.fullName, '');
      expect(identity.needsContact, isTrue);
      expect(identity.socialAvatarUrl, isNull);
    });
  });

  group('socialAvatarSourceUrl', () {
    test('foto do Google em 400 px', () {
      expect(
        socialAvatarSourceUrl('https://lh3.googleusercontent.com/a/abc=s96-c'),
        'https://lh3.googleusercontent.com/a/abc=s400-c',
      );
    });

    test('outros URLs ficam iguais', () {
      const fb = 'https://graph.facebook.com/1/picture?type=large';
      expect(socialAvatarSourceUrl(fb), fb);
    });
  });

  group('SocialSignInButtons', () {
    Widget app({bool? showFacebook}) => MaterialApp(
          home: Scaffold(
            body: showFacebook == null
                ? SocialSignInButtons(enabled: true, onPressed: (_) {})
                : SocialSignInButtons(
                    enabled: true,
                    onPressed: (_) {},
                    showFacebook: showFacebook,
                  ),
          ),
        );

    testWidgets('sem FACEBOOK_LOGIN_ENABLED: só o Google', (tester) async {
      await tester.pumpWidget(app());
      expect(find.text('Continuar com Google'), findsOneWidget);
      expect(find.text('Continuar com Facebook'), findsNothing);
      expect(find.textContaining('Google ou Facebook'), findsNothing);
    });

    testWidgets('com o Facebook ligado: os dois botões', (tester) async {
      await tester.pumpWidget(app(showFacebook: true));
      expect(find.text('Continuar com Google'), findsOneWidget);
      expect(find.text('Continuar com Facebook'), findsOneWidget);
      expect(find.textContaining('Google ou Facebook'), findsOneWidget);
    });
  });
}
