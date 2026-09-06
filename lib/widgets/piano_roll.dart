import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../utils/music_theory.dart';
import 'mini_amp_panel.dart';
import 'param_lock_sheet.dart';

class PianoRoll extends StatefulWidget {
  const PianoRoll({super.key, required this.track});

  final Track track;

  @override
  State<PianoRoll> createState() => _PianoRollState();
}

class _PianoRollState extends State<PianoRoll> {
  static const cellW = 22.0;
  static const cellHNormal = 18.0;
  static const cellHCollapsed = 28.0;
  static const lowMidi = 36; // C2
  static const highMidi = 84; // C6
  static const keyWNormal = 44.0;
  static const keyWCollapsed = 56.0;

  final _h = ScrollController();

  /// Cells touched during the current paint stroke (trail + dedupe).
  final Set<String> _strokeCells = {};
  bool _strokePaintOn = true;
  bool _strokeMoved = false;
  bool _pendingParamLock = false;
  int? _strokeStartMidi;
  int? _strokeStartStep;

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  String _cellKey(int midi, int step) => '$midi:$step';

  (int midi, int step)? _hit({
    required Offset local,
    required List<int> midiLanes,
    required double cellH,
    required int steps,
  }) {
    if (midiLanes.isEmpty) return null;
    final pitches = midiLanes.length;
    final row = (local.dy / cellH).floor().clamp(0, pitches - 1);
    final step = (local.dx / cellW).floor().clamp(0, steps - 1);
    if (local.dy < 0 || local.dy >= pitches * cellH) return null;
    if (local.dx < 0 || local.dx >= steps * cellW) return null;
    return (midiLanes[row], step);
  }

  Future<void> _openParamLock(
    BuildContext context,
    StudioController c, {
    required int midi,
    required int step,
  }) async {
    final note = c.findNote(widget.track, midi, step);
    if (note == null) return;
    final accent = Color(widget.track.colorValue);
    final result = await showParamLockSheet(
      context,
      accent: accent,
      velocity: note.velocity,
      probability: note.probability,
      lengthSteps: note.lengthSteps,
      showLength: true,
      title: 'Note lock · ${MusicTheory.noteName(midi)}',
    );
    if (result == null) return;
    if (result.delete) {
      c.beginNoteStroke(widget.track.id);
      c.paintNoteCell(
        trackId: widget.track.id,
        pitch: midi,
        startStep: step,
        on: false,
      );
      c.endNoteStroke(label: 'Delete note');
      return;
    }
    c.setNoteParams(
      trackId: widget.track.id,
      noteId: note.id,
      velocity: result.velocity,
      lengthSteps: result.lengthSteps,
      probability: result.probability,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project!;
    final steps = p.loopEndStep.clamp(16, 256);
    final accent = Color(widget.track.colorValue);
    // High → low so top of grid is higher pitch (no reverse ListView).
    final midiLanes = <int>[
      for (var m = highMidi; m >= lowMidi; m--)
        if (!c.scaleLock || MusicTheory.inScale(m, p.key, p.scale)) m,
    ];
    final pitches = midiLanes.length;
    final cellH = c.scaleLock ? cellHCollapsed : cellHNormal;
    final keyW = c.scaleLock ? keyWCollapsed : keyWNormal;
    final painting = _strokeCells.isNotEmpty;
    final hPhysics = painting ? const NeverScrollableScrollPhysics() : null;

    return Column(
      children: [
        if (c.pitchWarning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              c.pitchWarning!,
              style: const TextStyle(fontSize: 11, color: StudioColors.danger),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Scale lock'),
                selected: c.scaleLock,
                showCheckmark: false,
                selectedColor: accent.withValues(alpha: 0.35),
                onSelected: c.setScaleLock,
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(c.eraseMode ? 'Erase' : 'Draw'),
                selected: c.eraseMode,
                showCheckmark: false,
                onSelected: c.setEraseMode,
              ),
              const Spacer(),
              Text(
                'Vel ${c.drawVelocity}',
                style: const TextStyle(color: StudioColors.textDim, fontSize: 12),
              ),
              SizedBox(
                width: 100,
                child: Slider(
                  min: 20,
                  max: 127,
                  value: c.drawVelocity.toDouble(),
                  activeColor: accent,
                  onChanged: (v) => c.setDrawVelocity(v.round()),
                ),
              ),
            ],
          ),
        ),
        if (widget.track.category == TrackCategory.bass ||
            widget.track.category == TrackCategory.guitar)
          MiniAmpPanel(track: widget.track),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Text(
            c.scaleLock
                ? 'In-scale lanes · drag to paint · tap note for locks'
                : 'Drag to paint · tap note for velocity / length / prob',
            style: const TextStyle(fontSize: 10, color: StudioColors.textDim),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            // Vertical scroll shared by keys + grid (content-local hit testing).
            physics: painting
                ? const NeverScrollableScrollPhysics()
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: keyW,
                  child: Column(
                    children: [
                      for (final midi in midiLanes)
                        Container(
                          height: cellH,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 6),
                          color: MusicTheory.inScale(midi, p.key, p.scale)
                              ? StudioColors.surface2
                              : StudioColors.bg,
                          child: Text(
                            MusicTheory.noteName(midi),
                            style: TextStyle(
                              fontSize: c.scaleLock ? 11 : 9,
                              fontWeight: c.scaleLock
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: MusicTheory.inScale(midi, p.key, p.scale)
                                  ? StudioColors.text
                                  : StudioColors.textDim,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _h,
                    physics: hPhysics,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: steps * cellW,
                      height: pitches * cellH,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) {
                          final hit = _hit(
                            local: e.localPosition,
                            midiLanes: midiLanes,
                            cellH: cellH,
                            steps: steps,
                          );
                          if (hit == null) return;
                          final (midi, step) = hit;
                          final existing =
                              c.findNote(widget.track, midi, step);
                          _strokeCells
                            ..clear()
                            ..add(_cellKey(midi, step));
                          _strokeMoved = false;
                          _strokeStartMidi = midi;
                          _strokeStartStep = step;
                          _pendingParamLock = false;

                          if (c.eraseMode) {
                            _strokePaintOn = false;
                            c.beginNoteStroke(widget.track.id);
                            c.paintNoteCell(
                              trackId: widget.track.id,
                              pitch: midi,
                              startStep: step,
                              on: false,
                            );
                          } else if (existing != null) {
                            _strokePaintOn = false;
                            _pendingParamLock = true;
                            c.beginNoteStroke(widget.track.id);
                          } else {
                            _strokePaintOn = true;
                            c.beginNoteStroke(widget.track.id);
                            c.paintNoteCell(
                              trackId: widget.track.id,
                              pitch: midi,
                              startStep: step,
                              on: true,
                            );
                            c.triggerNote(widget.track, midi);
                          }
                          setState(() {});
                        },
                        onPointerMove: (e) {
                          if (_strokeStartMidi == null) return;
                          final hit = _hit(
                            local: e.localPosition,
                            midiLanes: midiLanes,
                            cellH: cellH,
                            steps: steps,
                          );
                          if (hit == null) return;
                          final (midi, step) = hit;
                          final key = _cellKey(midi, step);
                          final leftStart = midi != _strokeStartMidi ||
                              step != _strokeStartStep;
                          if (leftStart && !_strokeMoved) {
                            _strokeMoved = true;
                            if (_pendingParamLock) {
                              c.paintNoteCell(
                                trackId: widget.track.id,
                                pitch: _strokeStartMidi!,
                                startStep: _strokeStartStep!,
                                on: false,
                              );
                              _pendingParamLock = false;
                            }
                          }
                          if (_strokeCells.contains(key)) return;
                          _strokeCells.add(key);
                          if (_pendingParamLock) return;
                          c.paintNoteCell(
                            trackId: widget.track.id,
                            pitch: midi,
                            startStep: step,
                            on: _strokePaintOn,
                          );
                          if (_strokePaintOn) {
                            c.triggerNote(widget.track, midi);
                          }
                          setState(() {});
                        },
                        onPointerUp: (_) async {
                          final moved = _strokeMoved;
                          final startMidi = _strokeStartMidi;
                          final startStep = _strokeStartStep;
                          final pendingLock = _pendingParamLock;
                          final paintOn = _strokePaintOn;
                          c.endNoteStroke(
                            label: paintOn ? 'Paint notes' : 'Erase notes',
                          );
                          _strokeCells.clear();
                          _strokeStartMidi = null;
                          _strokeStartStep = null;
                          _pendingParamLock = false;
                          if (mounted) setState(() {});

                          if (!moved &&
                              pendingLock &&
                              startMidi != null &&
                              startStep != null) {
                            if (!context.mounted) return;
                            await _openParamLock(
                              context,
                              c,
                              midi: startMidi,
                              step: startStep,
                            );
                          }
                        },
                        onPointerCancel: (_) {
                          c.endNoteStroke(label: 'Paint notes');
                          _strokeCells.clear();
                          _strokeStartMidi = null;
                          _strokeStartStep = null;
                          _pendingParamLock = false;
                          if (mounted) setState(() {});
                        },
                        child: Column(
                          children: [
                            for (final midi in midiLanes)
                              Row(
                                children: [
                                  for (var s = 0; s < steps; s++)
                                    _Cell(
                                      width: cellW,
                                      height: cellH,
                                      beat: s % 4 == 0,
                                      bar: s % 16 == 0,
                                      playhead: c.playheadStep == s,
                                      inScale: MusicTheory.inScale(
                                          midi, p.key, p.scale),
                                      active: widget.track.notes.any(
                                        (n) =>
                                            n.pitch == midi &&
                                            n.startStep == s,
                                      ),
                                      trail: _strokeCells
                                          .contains(_cellKey(midi, s)),
                                      color: accent,
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.width,
    required this.height,
    required this.beat,
    required this.bar,
    required this.playhead,
    required this.inScale,
    required this.active,
    required this.trail,
    required this.color,
  });

  final double width;
  final double height;
  final bool beat;
  final bool bar;
  final bool playhead;
  final bool inScale;
  final bool active;
  final bool trail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: active
            ? color
            : trail
                ? color.withValues(alpha: 0.35)
                : (inScale ? const Color(0xFF151925) : StudioColors.bg),
        border: Border.all(
          color: playhead
              ? StudioColors.play
              : trail
                  ? color.withValues(alpha: 0.8)
                  : bar
                      ? StudioColors.border
                      : beat
                          ? const Color(0xFF222836)
                          : const Color(0xFF141820),
          width: playhead || trail ? 1.5 : 0.5,
        ),
      ),
    );
  }
}
