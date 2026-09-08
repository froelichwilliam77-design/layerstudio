import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:layerstudio/main.dart';

void main() {
  testWidgets('valid email shows a consent-gated analysis result', (
    tester,
  ) async {
    await tester.pumpWidget(const MosintApp());

    expect(find.text('Mosint'), findsOneWidget);
    expect(find.text('Analyze email'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'security@example.com');
    await tester.tap(find.text('Analyze email'));
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pump();

    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('CONSENT REQUIRED'), findsOneWidget);
    expect(find.textContaining('never credentials'), findsOneWidget);
  });
}
