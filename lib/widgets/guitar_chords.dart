import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../utils/music_theory.dart';
import 'mini_amp_panel.dart';

/// Expressive guitar chord mode: performative strum bars + harmonic tools.
///
/// Swipe down = downstroke (low→high), swipe up = upstroke (high→low).
/// Swipe speed maps to velocity; [strumOffsetMs] staggers notes for realism.
class GuitarChordStrips extends StatefulWidget {
  const GuitarChordStrips({super.key, required this.track});

  final Track track;

  @override
  State<GuitarChordStrips> createState() => _GuitarChordStripsState();
}

class _GuitarChordStripsState extends State<GuitarChordStrips> {
  /// Micro-timing stagger across chord notes (visual-guide ~10–40 ms).
  double _strumOffsetMs = 22;

  bool _extSeventh = false;
  bool _extSus4 = false;
  int _inversion = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project!;
    final rootPc = MusicTheory.pitchNames.indexOf(p.key).clamp(0, 11);
    final offsets = p.scale == 'minor'
        ? [0, 2, 3, 5, 7, 8, 10]
        : [0, 2, 4, 5, 7, 9, 11];
    final labels = p.scale == 'minor'
        ? ['i', 'ii°', 'III', 'iv', 'v', 'VI', 'VII']
        : ['I', 'ii', 'iii', 'IV', 'V', 'vi', 'vii°'];
    final minors = p.scale == 'minor'
        ? [true, true, false, true, true, false, false]
        : [false, true, true, false, false, true, true];
    final accent = StudioColors.guitarViolet;

    return Column(
      children: [
        MiniAmpPanel(track: widget.track),
        _HarmonicToolsPanel(
          accent: accent,
          strumOffsetMs: _strumOffsetMs,
          extSeventh: _extSeventh,
          extSus4: _extSus4,
          inversion: _inversion,
          onStrumOffset: (v) => setState(() => _strumOffsetMs = v),
          onSeventh: (v) => setState(() => _extSeventh = v),
          onSus4: (v) => setState(() => _extSus4 = v),
          onInversion: (v) => setState(() => _inversion = v),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            itemCount: 7,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final pc = (rootPc + offsets[i]) % 12;
              final rootMidi = 48 + pc;
              final isMinor = minors[i];
              // Dimished degrees don't take sus4 well; still allow tools.
              final notes = MusicTheory.chordVoicing(
                rootMidi,
                minor: isMinor,
                seventh: _extSeventh,
                sus4: _extSus4,
                inversion: _inversion,
              );
              final suffix = MusicTheory.chordSuffix(
                minor: isMinor,
                seventh: _extSeventh,
                sus4: _extSus4,
              );
              final name = '${MusicTheory.pitchNames[pc]}$suffix';
              return _StrumBar(
                track: widget.track,
                degreeLabel: labels[i],
                chordName: name,
                notes: notes,
                accent: accent,
                strumOffsetMs: _strumOffsetMs,
                extensionsActive: _extSeventh || _extSus4 || _inversion > 0,
                inversion: _inversion,
                seventh: _extSeventh,
                sus4: _extSus4,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HarmonicToolsPanel extends StatelessWidget {
  const _HarmonicToolsPanel({
    required this.accent,
    required this.strumOffsetMs,
    required this.extSeventh,
    required this.extSus4,
    required this.inversion,
    required this.onStrumOffset,
    required this.onSeventh,
    required this.onSus4,
    required this.onInversion,
  });

  final Color accent;
  final double strumOffsetMs;
  final bool extSeventh;
  final bool extSus4;
  final int inversion;
  final ValueChanged<double> onStrumOffset;
  final ValueChanged<bool> onSeventh;
  final ValueChanged<bool> onSus4;
  final ValueChanged<int> onInversion;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: StudioColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 16, color: accent),
              const SizedBox(width: 8),
              const Text(
                'Harmonic tools',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
              const Spacer(),
              Text(
                '↓ down · ↑ up · speed = velocity',
                style: TextStyle(
                  fontSize: 10,
                  color: StudioColors.textDim.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(
                width: 88,
                child: Text(
                  'Strum offset',
                  style: TextStyle(fontSize: 11, color: StudioColors.textDim),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: accent,
                    inactiveTrackColor: StudioColors.border,
                    thumbColor: accent,
                  ),
                  child: Slider(
                    min: 10,
                    max: 40,
                    divisions: 30,
                    value: strumOffsetMs.clamp(10, 40),
                    label: '${strumOffsetMs.round()} ms',
                    onChanged: onStrumOffset,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${strumOffsetMs.round()}ms',
                  style: TextStyle(fontSize: 11, color: accent),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                width: 88,
                child: Text(
                  'Extensions',
                  style: TextStyle(fontSize: 11, color: StudioColors.textDim),
                ),
              ),
              FilterChip(
                label: const Text('7th'),
                selected: extSeventh,
                onSelected: onSeventh,
                selectedColor: accent.withValues(alpha: 0.35),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('sus4'),
                selected: extSus4,
                onSelected: onSus4,
                selectedColor: accent.withValues(alpha: 0.35),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 12),
              ),
              const Spacer(),
              const Text(
                'Inv',
                style: TextStyle(fontSize: 11, color: StudioColors.textDim),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: inversion > 0
                    ? () => onInversion(inversion - 1)
                    : null,
                icon: const Icon(Icons.remove, size: 18),
                color: accent,
              ),
              Text(
                '$inversion',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: inversion < 3
                    ? () => onInversion(inversion + 1)
                    : null,
                icon: const Icon(Icons.add, size: 18),
                color: accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StrumBar extends StatefulWidget {
  const _StrumBar({
    required this.track,
    required this.degreeLabel,
    required this.chordName,
    required this.notes,
    required this.accent,
    required this.strumOffsetMs,
    required this.extensionsActive,
    required this.inversion,
    required this.seventh,
    required this.sus4,
  });

  final Track track;
  final String degreeLabel;
  final String chordName;
  final List<int> notes;
  final Color accent;
  final double strumOffsetMs;
  final bool extensionsActive;
  final int inversion;
  final bool seventh;
  final bool sus4;

  @override
  State<_StrumBar> createState() => _StrumBarState();
}

class _StrumBarState extends State<_StrumBar> {
  /// -1 idle; otherwise how many note lines are lit during a strum.
  int _litCount = -1;
  bool _downstroke = true;
  double _dragAccumDy = 0;
  DateTime? _dragStart;
  int _strumGen = 0;

  Future<void> _performStrum({
    required bool downstroke,
    required double velocity,
  }) async {
    final c = context.read<StudioController>();
    final notes = List<int>.from(widget.notes);
    if (!downstroke) {
      notes.sort((a, b) => b.compareTo(a)); // high → low
    } else {
      notes.sort((a, b) => a.compareTo(b)); // low → high
    }
    final gen = ++_strumGen;
    final offset = Duration(
      milliseconds: widget.strumOffsetMs.round().clamp(10, 40),
    );
    final vel = velocity.clamp(0.28, 1.0);

    HapticFeedback.selectionClick();

    for (var i = 0; i < notes.length; i++) {
      if (!mounted || gen != _strumGen) return;
      setState(() {
        _downstroke = downstroke;
        _litCount = i + 1;
      });
      // Existing playback path — staggered for strum realism.
      unawaited(c.triggerNote(widget.track, notes[i], velocity: vel));
      if (c.isPlaying) {
        c.addOrToggleNote(
          trackId: widget.track.id,
          pitch: notes[i],
          startStep: c.playheadStep,
          lengthSteps: 4,
        );
      }
      if (i < notes.length - 1) {
        await Future<void>.delayed(offset);
      }
    }
    if (!mounted || gen != _strumGen) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted || gen != _strumGen) return;
    setState(() => _litCount = -1);
  }

  void _onDragStart(DragStartDetails _) {
    _dragAccumDy = 0;
    _dragStart = DateTime.now();
    setState(() {
      _litCount = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _dragAccumDy += d.delta.dy;
    final n = widget.notes.length;
    if (n == 0) return;
    // Preview stagger: map travel distance to lit note count.
    final progress = (_dragAccumDy.abs() / 48.0).clamp(0.0, 1.0);
    final lit = (progress * n).ceil().clamp(0, n);
    final down = _dragAccumDy >= 0;
    if (lit != _litCount || down != _downstroke) {
      setState(() {
        _litCount = lit;
        _downstroke = down;
      });
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final dy = _dragAccumDy;
    final elapsedMs = math.max(
      1,
      DateTime.now().difference(_dragStart ?? DateTime.now()).inMilliseconds,
    );
    final pxPerSec = (dy.abs() / elapsedMs) * 1000.0;
    // Also fold in fling velocity when present.
    final fling = d.primaryVelocity?.abs() ?? 0;
    final speed = math.max(pxPerSec, fling);
    // Map ~200–2400 px/s → 0.35–1.0
    final velocity = (0.28 + (speed / 2200.0) * 0.72).clamp(0.28, 1.0);

    if (dy.abs() < 6 && speed < 80) {
      // Treat as tap → medium downstroke.
      unawaited(_performStrum(downstroke: true, velocity: 0.85));
      return;
    }
    unawaited(
      _performStrum(downstroke: dy >= 0, velocity: velocity),
    );
  }

  void _onTap() {
    unawaited(_performStrum(downstroke: true, velocity: 0.85));
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final notes = widget.notes;
    final lit = _litCount;

    return Material(
      color: accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: lit >= 0
                  ? accent.withValues(alpha: 0.85)
                  : StudioColors.border,
              width: lit >= 0 ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: StudioColors.surface2,
                child: Text(
                  widget.degreeLabel,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 78,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.chordName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (widget.extensionsActive) ...[
                          const SizedBox(width: 4),
                          _ExtDot(
                            color: accent,
                            tooltip: [
                              if (widget.seventh) '7',
                              if (widget.sus4) 'sus4',
                              if (widget.inversion > 0)
                                'inv${widget.inversion}',
                            ].join(' · '),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      lit >= 0
                          ? (_downstroke ? '↓ downstroke' : '↑ upstroke')
                          : 'strum bar',
                      style: TextStyle(
                        fontSize: 10,
                        color: lit >= 0 ? accent : StudioColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CustomPaint(
                  painter: _NoteLinesPainter(
                    noteCount: notes.length,
                    litCount: lit < 0 ? 0 : lit,
                    accent: accent,
                    downstroke: _downstroke,
                    active: lit >= 0,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(width: 6),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.keyboard_arrow_up, size: 16, color: accent.withValues(alpha: 0.7)),
                  Icon(Icons.swipe_vertical, size: 18, color: StudioColors.textDim),
                  Icon(Icons.keyboard_arrow_down, size: 16, color: accent.withValues(alpha: 0.7)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtDot extends StatelessWidget {
  const _ExtDot({required this.color, required this.tooltip});
  final Color color;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.55),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical note lines — one per chord tone — lit progressively while strumming.
class _NoteLinesPainter extends CustomPainter {
  _NoteLinesPainter({
    required this.noteCount,
    required this.litCount,
    required this.accent,
    required this.downstroke,
    required this.active,
  });

  final int noteCount;
  final int litCount;
  final Color accent;
  final bool downstroke;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (noteCount <= 0) return;
    final padY = 10.0;
    final h = size.height - padY * 2;
    final gap = size.width / (noteCount + 1);
    for (var i = 0; i < noteCount; i++) {
      // Visual order: left = low for downstroke preview, or reverse for up.
      final visualIndex = downstroke ? i : (noteCount - 1 - i);
      final lit = active && visualIndex < litCount;
      final x = gap * (i + 1);
      final paint = Paint()
        ..color = lit
            ? accent
            : accent.withValues(alpha: active ? 0.35 : 0.45)
        ..strokeWidth = lit ? 3.2 : 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, padY), Offset(x, padY + h), paint);
      if (lit) {
        final glow = Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawLine(Offset(x, padY), Offset(x, padY + h), glow);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NoteLinesPainter old) =>
      old.noteCount != noteCount ||
      old.litCount != litCount ||
      old.accent != accent ||
      old.downstroke != downstroke ||
      old.active != active;
}
