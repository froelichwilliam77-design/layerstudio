import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_event.dart';
import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../utils/music_theory.dart';
import 'note_lock_sheet.dart';

class PianoRoll extends StatefulWidget {
  const PianoRoll({super.key, required this.track});

  final Track track;

  @override
  State<PianoRoll> createState() => _PianoRollState();
}

class _PianoRollState extends State<PianoRoll> {
  static const cellW = 24.0;
  static const cellH = 20.0;
  static const lowMidi = 36;
  static const highMidi = 84;

  final _h = ScrollController();
  final _vKeys = ScrollController();
  final _vGrid = ScrollController();

  bool _painting = false;
  int? _lastPaintPitch;
  int? _lastPaintStep;

  @override
  void dispose() {
    _h.dispose();
    _vKeys.dispose();
    _vGrid.dispose();
    super.dispose();
  }

  List<int> _visiblePitches(StudioController c) {
    final p = c.project!;
    final all = [for (var m = lowMidi; m <= highMidi; m++) m];
    if (!c.scaleLock) return all;
    return all.where((m) => MusicTheory.inScale(m, p.key, p.scale)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project!;
    final steps = p.loopEndStep.clamp(16, 256);
    final pitches = _visiblePitches(c);
    final accent = Color(widget.track.colorValue);

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
                onSelected: c.setScaleLock,
                selectedColor: accent.withValues(alpha: 0.35),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: Text(c.eraseMode ? 'Erase' : 'Paint'),
                selected: c.eraseMode,
                onSelected: c.setEraseMode,
                selectedColor: StudioColors.danger.withValues(alpha: 0.35),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              ),
              const Spacer(),
              Text(
                'Vel ${c.drawVelocity}',
                style: const TextStyle(color: StudioColors.textDim, fontSize: 12),
              ),
              SizedBox(
                width: 90,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: accent,
                    thumbColor: accent,
                  ),
                  child: Slider(
                    min: 20,
                    max: 127,
                    value: c.drawVelocity.toDouble(),
                    onChanged: (v) => c.setDrawVelocity(v.round()),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollUpdateNotification &&
                        _vGrid.hasClients &&
                        _vKeys.hasClients) {
                      _vGrid.jumpTo(_vKeys.offset.clamp(
                        _vGrid.position.minScrollExtent,
                        _vGrid.position.maxScrollExtent,
                      ));
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _vKeys,
                    itemCount: pitches.length,
                    itemExtent: cellH,
                    reverse: true,
                    itemBuilder: (_, i) {
                      final midi = pitches[i];
                      return Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 4),
                        color: accent.withValues(alpha: 0.12),
                        child: Text(
                          MusicTheory.noteName(midi),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollUpdateNotification &&
                        _vKeys.hasClients &&
                        _vGrid.hasClients) {
                      _vKeys.jumpTo(_vGrid.offset.clamp(
                        _vKeys.position.minScrollExtent,
                        _vKeys.position.maxScrollExtent,
                      ));
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _h,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: steps * cellW,
                      child: ListView.builder(
                        controller: _vGrid,
                        itemCount: pitches.length,
                        itemExtent: cellH,
                        reverse: true,
                        itemBuilder: (_, i) {
                          final midi = pitches[i];
                          return Row(
                            children: [
                              for (var s = 0; s < steps; s++)
                                _Cell(
                                  width: cellW,
                                  height: cellH,
                                  beat: s % 4 == 0,
                                  bar: s % 16 == 0,
                                  playhead: c.playheadStep == s,
                                  note: c.noteAt(widget.track, midi, s),
                                  color: accent,
                                  onTap: () => _onTap(c, midi, s),
                                  onPaintEnter: () => _onPaint(c, midi, s),
                                  onPaintStart: () {
                                    _painting = true;
                                    _lastPaintPitch = null;
                                    _lastPaintStep = null;
                                    _onPaint(c, midi, s);
                                  },
                                  onPaintEnd: () => _painting = false,
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _onTap(StudioController c, int midi, int step) {
    final existing = c.noteAt(widget.track, midi, step);
    if (existing != null && !c.eraseMode) {
      showNoteLockSheet(
        context: context,
        note: existing,
        accent: Color(widget.track.colorValue),
        onChanged: ({velocity, lengthSteps, probability}) {
          c.updateNoteParams(
            trackId: widget.track.id,
            noteId: existing.id,
            velocity: velocity,
            lengthSteps: lengthSteps,
            probability: probability,
          );
        },
      );
      return;
    }
    c.addOrToggleNote(
      trackId: widget.track.id,
      pitch: midi,
      startStep: step,
    );
    if (!c.eraseMode) c.triggerNote(widget.track, midi);
  }

  void _onPaint(StudioController c, int midi, int step) {
    if (!_painting && !c.eraseMode) return;
    if (_lastPaintPitch == midi && _lastPaintStep == step) return;
    _lastPaintPitch = midi;
    _lastPaintStep = step;
    if (c.eraseMode) {
      c.addOrToggleNote(
        trackId: widget.track.id,
        pitch: midi,
        startStep: step,
      );
    } else {
      c.paintNote(
        trackId: widget.track.id,
        pitch: midi,
        startStep: step,
      );
      c.triggerNote(widget.track, midi);
    }
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.width,
    required this.height,
    required this.beat,
    required this.bar,
    required this.playhead,
    required this.note,
    required this.color,
    required this.onTap,
    required this.onPaintEnter,
    required this.onPaintStart,
    required this.onPaintEnd,
  });

  final double width;
  final double height;
  final bool beat;
  final bool bar;
  final bool playhead;
  final NoteEvent? note;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onPaintEnter;
  final VoidCallback onPaintStart;
  final VoidCallback onPaintEnd;

  @override
  Widget build(BuildContext context) {
    final active = note != null;
    final vel = (note?.velocity ?? 100) / 127.0;
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (_) => onPaintStart(),
      onLongPressMoveUpdate: (_) => onPaintEnter(),
      onLongPressEnd: (_) => onPaintEnd(),
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.bottomCenter,
        decoration: BoxDecoration(
          color: active
              ? null
              : (beat ? const Color(0xFF151925) : StudioColors.bg),
          border: Border.all(
            color: playhead
                ? StudioColors.play
                : bar
                    ? StudioColors.border
                    : beat
                        ? const Color(0xFF222836)
                        : const Color(0xFF141820),
            width: playhead ? 1.5 : 0.5,
          ),
        ),
        child: active
            ? Container(
                width: width - 2,
                height: (height - 2) * vel.clamp(0.25, 1.0),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.55 + vel * 0.45),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 4,
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}
