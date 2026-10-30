import 'package:duo/features/auth/auth_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('validates the form before calling the API', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: LoginScreen())));
    await tester.ensureVisible(find.text('sign in'));
    await tester.tap(find.text('sign in'));
    await tester.pump();

    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });
}
