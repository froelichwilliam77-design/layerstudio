import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/services/command_stack.dart';

void main() {
  test('undo/redo stack restores snapshots', () {
    var value = 0;
    final stack = CommandStack();
    stack.push(
      NotesSnapshotCommand(
        label: 'set',
        apply: (snap) {
          value = snap['v']!.first as int;
        },
        before: {
          'v': [0]
        },
        after: {
          'v': [7]
        },
      ),
    );
    expect(value, 7);
    expect(stack.canUndo, isTrue);
    stack.undo();
    expect(value, 0);
    expect(stack.canRedo, isTrue);
    stack.redo();
    expect(value, 7);
  });
}
