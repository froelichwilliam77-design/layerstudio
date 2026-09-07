import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/reddit_archive_app.dart';

void main() {
  testWidgets('filters archive records and displays responsible-use guidance', (
    tester,
  ) async {
    await tester.pumpWidget(const TraceArchiveApp());

    expect(find.text('Search the public record'), findsOneWidget);
    expect(find.text('3 matching records'), findsNothing);

    await tester.tap(find.text('Removed only'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.text('1 matching records'), findsOneWidget);
    expect(find.text('REMOVED'), findsOneWidget);

    await tester.tap(find.byTooltip('About archive data'));
    await tester.pumpAndSettle();
    expect(find.text('Public archive, responsible use'), findsOneWidget);
  });
}
