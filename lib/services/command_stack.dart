/// Simple undo/redo command stack for note/pattern edits.
abstract class StudioCommand {
  String get label;
  void execute();
  void undo();
}

class CommandStack {
  CommandStack({this.maxDepth = 64});

  final int maxDepth;
  final List<StudioCommand> _undo = [];
  final List<StudioCommand> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.label;

  void push(StudioCommand cmd, {bool executeNow = true}) {
    if (executeNow) cmd.execute();
    _undo.add(cmd);
    if (_undo.length > maxDepth) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final cmd = _undo.removeLast();
    cmd.undo();
    _redo.add(cmd);
  }

  void redo() {
    if (_redo.isEmpty) return;
    final cmd = _redo.removeLast();
    cmd.execute();
    _undo.add(cmd);
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}

/// Full project JSON snapshot (mixer, arrange, meta, FX).
class JsonSnapshotCommand implements StudioCommand {
  JsonSnapshotCommand({
    required this.label,
    required this.apply,
    required this.before,
    required this.after,
  });

  @override
  final String label;
  final void Function(String json) apply;
  final String before;
  final String after;

  @override
  void execute() => apply(after);

  @override
  void undo() => apply(before);
}

/// Captures before/after note lists for one or more tracks.
class NotesSnapshotCommand implements StudioCommand {
  NotesSnapshotCommand({
    required this.label,
    required this.apply,
    required this.before,
    required this.after,
  });

  @override
  final String label;
  final void Function(Map<String, List<dynamic>> snapshot) apply;
  final Map<String, List<dynamic>> before;
  final Map<String, List<dynamic>> after;

  @override
  void execute() => apply(after);

  @override
  void undo() => apply(before);
}
