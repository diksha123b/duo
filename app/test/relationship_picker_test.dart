import 'package:duo/core/models.dart';
import 'package:duo/features/pairing/relationship_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<RelationshipChoice?>> pump(WidgetTester tester) async {
    final seen = <RelationshipChoice?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: RelationshipPicker(onChanged: seen.add)),
        ),
      ),
    );
    return seen;
  }

  testWidgets('offers many presets beyond the basics', (tester) async {
    await pump(tester);
    for (final chip in ['cousin', 'roommate', 'coworker', 'grandparent / grandkid', 'something else']) {
      expect(find.textContaining(chip), findsOneWidget);
    }
  });

  testWidgets('a preset maps to its tone and label', (tester) async {
    final seen = await pump(tester);
    await tester.tap(find.textContaining('cousin'));
    await tester.pump();
    expect(seen.last!.tone, Relationship.siblings);
    expect(seen.last!.label, 'cousins');
    expect(seen.last!.complete, isTrue);
  });

  testWidgets('grown-up/young presets ask which one you are', (tester) async {
    final seen = await pump(tester);
    await tester.tap(find.textContaining('grandparent / grandkid'));
    await tester.pump();
    expect(seen.last!.complete, isFalse);
    await tester.tap(find.textContaining('🧒 grandkid'));
    await tester.pump();
    expect(seen.last!.role, FamilyRole.child);
    expect(seen.last!.complete, isTrue);
  });

  testWidgets('something else takes your own words and a vibe', (tester) async {
    final seen = await pump(tester);
    await tester.tap(find.textContaining('something else'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'gym buddies');
    await tester.tap(find.textContaining('💼 work'));
    await tester.pump();
    expect(seen.last!.label, 'gym buddies');
    expect(seen.last!.tone, Relationship.colleagues);
  });
}
