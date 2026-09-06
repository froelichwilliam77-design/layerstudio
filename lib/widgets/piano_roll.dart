import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../utils/music_theory.dart';
import 'mini_amp_panel.dart';

class PianoRoll extends StatefulWidget {
  const PianoRoll({super.key, required this.track});

  final Track track;

  @override
  State<PianoRoll> createState() => _PianoRollState();
}

class _PianoRollState extends State<PianoRoll> {
  static const cellW = 22.0;
  static const cellH = 18.0;
  static const lowMidi = 36; // C2
  static const highMidi = 84; // C6

  final _h = ScrollController();
  final _v = ScrollController();

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project!;
    final steps = p.loopEndStep.clamp(16, 256);
    final accent = Color(widget.track.colorValue);
    // Scale lock collapses off-key lanes (especially useful for bass piano roll).
    final midiLanes = <int>[
      for (var m = lowMidi; m <= highMidi; m++)
        if (!c.scaleLock || MusicTheory.inScale(m, p.key, p.scale)) m,
    ];
    final pitches = midiLanes.length;

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
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: ListView.builder(
                  controller: _v,
                  itemCount: pitches,
                  itemExtent: cellH,
                  reverse: true,
                  itemBuilder: (_, i) {
                    final midi = midiLanes[i];
                    final inScale =
                        MusicTheory.inScale(midi, p.key, p.scale);
                    return Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 4),
                      color: inScale
                          ? StudioColors.surface2
                          : StudioColors.bg,
                      child: Text(
                        MusicTheory.noteName(midi),
                        style: TextStyle(
                          fontSize: 9,
                          color: inScale
                              ? StudioColors.text
                              : StudioColors.textDim,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _h,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: steps * cellW,
                      child: ListView.builder(
                        itemCount: pitches,
                        itemExtent: cellH,
                        reverse: true,
                        itemBuilder: (_, i) {
                          final midi = midiLanes[i];
                          final inScale =
                              MusicTheory.inScale(midi, p.key, p.scale);
                          return Row(
                            children: [
                              for (var s = 0; s < steps; s++)
                                _Cell(
                                  width: cellW,
                                  height: cellH,
                                  beat: s % 4 == 0,
                                  bar: s % 16 == 0,
                                  playhead: c.playheadStep == s,
                                  inScale: inScale,
                                  active: widget.track.notes.any(
                                    (n) =>
                                        n.pitch == midi && n.startStep == s,
                                  ),
                                  color: accent,
                                  onTap: () {
                                    c.addOrToggleNote(
                                      trackId: widget.track.id,
                                      pitch: midi,
                                      startStep: s,
                                    );
                                    if (!c.eraseMode) {
                                      c.triggerNote(widget.track, midi);
                                    }
                                  },
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
    required this.color,
    required this.onTap,
  });

  final double width;
  final double height;
  final bool beat;
  final bool bar;
  final bool playhead;
  final bool inScale;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: active
              ? color
              : (inScale ? const Color(0xFF151925) : StudioColors.bg),
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
      ),
    );
  }
}
