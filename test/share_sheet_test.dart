import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/utils/share_sheet.dart';

void main() {
  test('shareSheetOriginFallback is a non-empty iPad-safe rect', () {
    expect(shareSheetOriginFallback.width, greaterThan(0));
    expect(shareSheetOriginFallback.height, greaterThan(0));
  });

  testWidgets('shareSheetOrigin uses the widget box when laid out', (
    tester,
  ) async {
    late Rect origin;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return SizedBox(
                width: 80,
                height: 40,
                child: GestureDetector(
                  onTap: () => origin = shareSheetOrigin(context),
                  child: const Text('Share'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Share'));
    expect(origin.width, 80);
    expect(origin.height, 40);
  });

  test('shareSheetOrigin null context falls back', () {
    expect(shareSheetOrigin(null), shareSheetOriginFallback);
  });
}
