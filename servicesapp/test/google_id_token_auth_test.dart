import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/features/auth/data/google_id_token_auth.dart';
import 'package:servicesapp/features/auth/presentation/widgets/social_sign_in_buttons.dart';

void main() {
  test('sem GOOGLE_WEB_CLIENT_ID fica no login antigo por browser', () {
    expect(GoogleIdTokenAuth.webClientId, isEmpty);
    expect(GoogleIdTokenAuth.enabled, isFalse);
  });

  testWidgets('sem o ID, o botão próprio continua a aparecer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SocialSignInButtons(
            enabled: true,
            onPressed: (_) {},
            onGoogleIdToken: (_) {},
            showFacebook: false,
          ),
        ),
      ),
    );
    expect(find.text('Continuar com Google'), findsOneWidget);
  });
}
