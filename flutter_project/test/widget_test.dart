import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens_api/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginScreen()));

    expect(find.text('Вход'), findsWidgets);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Войти'), findsOneWidget);
  });
}
