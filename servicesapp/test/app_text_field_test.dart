import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servicesapp/core/widgets/app_text_field.dart';

class _PasswordHarness extends StatefulWidget {
  const _PasswordHarness({required this.controller});

  final TextEditingController controller;

  @override
  State<_PasswordHarness> createState() => _PasswordHarnessState();
}

class _PasswordHarnessState extends State<_PasswordHarness> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: widget.controller,
      label: 'Senha',
      obscureText: _obscure,
      autofillHints: const [AutofillHints.password],
      suffixIcon: IconButton(
        icon: const Icon(Icons.visibility_outlined),
        onPressed: () => setState(() => _obscure = !_obscure),
      ),
    );
  }
}

void main() {
  testWidgets('mostrar e esconder a senha mantém o texto e deixa escrever',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _PasswordHarness(controller: controller)),
    ));

    await tester.enterText(find.byType(TextField), 'Abc');
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(controller.text, 'Abc');
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, false);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Abcdef12');
    expect(controller.text, 'Abcdef12');

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(controller.text, 'Abcdef12');
    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, true);
  });
}
