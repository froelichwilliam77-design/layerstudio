import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../utils/music_theory.dart';
import 'mini_amp_panel.dart';

/// Perspective fretboard for bass (4) or guitar (6). Tap frets to play.
class InstrumentFretboard extends StatefulWidget {
  const InstrumentFretboard({super.key, required this.track});

  final Track track;

  @override
  State<InstrumentFretboard> createState() => _InstrumentFretboardState();
}

class _InstrumentFretboardState extends State<InstrumentFretboard> {
  static const bassOpen = [28, 33, 38, 43]; // E A D G
  static const guitarOpen = [40, 45, 50, 55, 59, 64]; // E A D G B E
  static const frets = 13;
  static const markers = {3, 5, 7, 9, 12};

  int? _litString;
  int? _litFret;

  List<int> get _openStrings =>
      widget.track.category == TrackCategory.guitar ? guitarOpen : bassOpen;

  String get _tuningLabel =>
      widget.track.category == TrackCategory.guitar ? 'E A D G B E' : 'E A D G';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project!;
    final accent = widget.track.category == TrackCategory.bass
        ? StudioColors.bassCyan
        : Color(widget.track.colorValue);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Scale lock'),
                selected: c.scaleLock,
                onSelected: c.setScaleLock,
                selectedColor: accent.withValues(alpha: 0.35),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              Text(
                '$_tuningLabel · tap frets',
                style: const TextStyle(fontSize: 11, color: StudioColors.textDim),
              ),
            ],
          ),
        ),
        MiniAmpPanel(track: widget.track),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: LayoutBuilder(
              builder: (context, box) {
                return CustomPaint(
                  painter: _FretboardPainter(
                    accent: accent,
                    scaleLock: c.scaleLock,
                    keyName: p.key,
                    scale: p.scale,
                    openStrings: _openStrings,
                    litString: _litString,
                    litFret: _litFret,
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _hit(c, box.biggest, d.localPosition),
                    onPanUpdate: (d) => _hit(c, box.biggest, d.localPosition),
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _hit(StudioController c, Size size, Offset pos) {
    final nStrings = _openStrings.length;
    final topInset = size.width * 0.08;
    final bottomInset = size.width * 0.02;
    final yT = (pos.dy / size.height).clamp(0.0, 0.999);
    final inset = topInset + (bottomInset - topInset) * yT;
    final usableW = size.width - inset * 2;
    if (pos.dx < inset || pos.dx > size.width - inset) return;
    final stringIndex = (yT * nStrings).floor().clamp(0, nStrings - 1);
    final fret =
        (((pos.dx - inset) / usableW) * frets).floor().clamp(0, frets - 1);
    final midi = _openStrings[stringIndex] + fret;
    if (c.scaleLock &&
        !MusicTheory.inScale(midi, c.project!.key, c.project!.scale)) {
      return;
    }
    setState(() {
      _litString = stringIndex;
      _litFret = fret;
    });
    c.triggerNote(widget.track, midi);
    if (c.isPlaying) {
      c.addOrToggleNote(
        trackId: widget.track.id,
        pitch: midi,
        startStep: c.playheadStep,
        lengthSteps: 2,
      );
    }
  }
}

/// Backward-compatible alias used by studio editor.
typedef BassFretboard = InstrumentFretboard;

class _FretboardPainter extends CustomPainter {
  _FretboardPainter({
    required this.accent,
    required this.scaleLock,
    required this.keyName,
    required this.scale,
    required this.openStrings,
    required this.litString,
    required this.litFret,
  });

  final Color accent;
  final bool scaleLock;
  final String keyName;
  final String scale;
  final List<int> openStrings;
  final int? litString;
  final int? litFret;

  static const frets = _InstrumentFretboardState.frets;
  static const markers = _InstrumentFretboardState.markers;

  @override
  void paint(Canvas canvas, Size size) {
    final nStrings = openStrings.length;
    final topInset = size.width * 0.08;
    final bottomInset = size.width * 0.02;
    final board = Path()
      ..moveTo(topInset, 0)
      ..lineTo(size.width - topInset, 0)
      ..lineTo(size.width - bottomInset, size.height)
      ..lineTo(bottomInset, size.height)
      ..close();
    canvas.drawPath(
      board,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1A12), Color(0xFF1A100C), Color(0xFF24160F)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      board,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: 0.35),
    );

    Offset fretPoint(int fret, double yT) {
      final inset = topInset + (bottomInset - topInset) * yT;
      final usableW = size.width - inset * 2;
      return Offset(inset + usableW * (fret / frets), size.height * yT);
    }

    for (var f = 0; f <= frets; f++) {
      canvas.drawLine(
        fretPoint(f, 0),
        fretPoint(f, 1),
        Paint()
          ..color = f == 0
              ? const Color(0xFFE8E0D0)
              : const Color(0xFF8A8070).withValues(alpha: 0.85)
          ..strokeWidth = f == 0 ? 3.5 : 1.2,
      );
    }

    for (final m in markers) {
      final mid = fretPoint(m, 0.5);
      final prev = fretPoint(m - 1, 0.5);
      final cx = (mid.dx + prev.dx) / 2;
      final paint = Paint()..color = const Color(0xFFD0C8B8).withValues(alpha: 0.5);
      if (m == 12) {
        canvas.drawCircle(Offset(cx, size.height * 0.28), 4, paint);
        canvas.drawCircle(Offset(cx, size.height * 0.72), 4, paint);
      } else {
        canvas.drawCircle(Offset(cx, size.height * 0.5), 4.5, paint);
      }
    }

    for (var s = 0; s < nStrings; s++) {
      final yT = (s + 0.5) / nStrings;
      canvas.drawLine(
        fretPoint(0, yT),
        fretPoint(frets, yT),
        Paint()
          ..color = Color.lerp(const Color(0xFFB0B8C8), accent, 0.2)!
          ..strokeWidth = (2.4 - s * 0.18).clamp(1.2, 2.4)
          ..strokeCap = StrokeCap.round,
      );
      for (var f = 0; f < frets; f++) {
        final midi = openStrings[s] + f;
        final inKey = MusicTheory.inScale(midi, keyName, scale);
        // Scale lock: highlight only in-key frets (bass cyan / track accent).
        // Unlocked: faint dots on every fret so the board stays playable.
        if (scaleLock && !inKey) continue;
        final left = fretPoint(f, yT);
        final right = fretPoint(f + 1, yT);
        final cx = (left.dx + right.dx) / 2;
        final cy = left.dy;
        final lit = litString == s && litFret == f;
        final alpha = scaleLock
            ? (lit ? 0.95 : 0.5)
            : (lit ? 0.9 : (inKey ? 0.28 : 0.12));
        canvas.drawCircle(
          Offset(cx, cy),
          lit ? 9.0 : 5.5,
          Paint()
            ..color = accent.withValues(alpha: alpha)
            ..maskFilter =
                lit ? const MaskFilter.blur(BlurStyle.normal, 6) : null,
        );
        canvas.drawCircle(
          Offset(cx, cy),
          lit ? 5.5 : 3.5,
          Paint()..color = accent.withValues(alpha: lit ? 1 : (scaleLock ? 0.75 : 0.4)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FretboardPainter old) =>
      old.accent != accent ||
      old.scaleLock != scaleLock ||
      old.keyName != keyName ||
      old.scale != scale ||
      old.openStrings != openStrings ||
      old.litString != litString ||
      old.litFret != litFret;
}
