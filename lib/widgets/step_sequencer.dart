import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/sound_library.dart';
import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

class StepSequencer extends StatelessWidget {
  const StepSequencer({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project!;
    final preset = SoundLibrary.byId(track.presetId);
    final kit = preset?.drumKit;
    if (kit == null) return const SizedBox.shrink();
    final names = kit.keys.toList();
    const steps = 16;
    final pages = (p.loopEndStep / steps).ceil().clamp(1, 8);
    final trackColor = StudioColors.forTrack(track);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Row(
            children: [
              Text(
                '16-step',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: trackColor,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < p.patterns.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        _PatternPill(
                          label: p.patterns[i].name,
                          selected: p.activePatternIndex == i,
                          color: trackColor,
                          onTap: () => c.selectPattern(i),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'clear_pattern':
                      c.clearPattern(p.activePatternIndex);
                    case 'clear_track':
                      c.clearTrackNotes(track.id);
                    case 'clear_all':
                      c.clearTrackAllPatterns(track.id);
                    case 'copy_to_b':
                      c.copyPattern(
                          fromIndex: p.activePatternIndex, toIndex: 1);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'clear_pattern', child: Text('Clear pattern')),
                  PopupMenuItem(
                      value: 'clear_track',
                      child: Text('Clear track (pattern)')),
                  PopupMenuItem(
                      value: 'clear_all',
                      child: Text('Clear track (all patterns)')),
                  PopupMenuItem(
                      value: 'copy_to_b', child: Text('Copy pattern → B')),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
          child: Row(
            children: [
              Text(
                'Vel ${c.drawVelocity}',
                style: const TextStyle(
                    fontSize: 11, color: StudioColors.textDim),
              ),
              Expanded(
                child: Slider(
                  min: 20,
                  max: 127,
                  value: c.drawVelocity.toDouble(),
                  activeColor: trackColor,
                  onChanged: (v) => c.setDrawVelocity(v.round()),
                ),
              ),
              Text(
                'Prob ${c.drawProbability}%',
                style: const TextStyle(
                    fontSize: 11, color: StudioColors.textDim),
              ),
              SizedBox(
                width: 72,
                child: Slider(
                  min: 0,
                  max: 100,
                  divisions: 20,
                  value: c.drawProbability.toDouble(),
                  onChanged: (v) => c.setDrawProbability(v.round()),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: pages,
            itemBuilder: (context, page) {
              final offset = page * steps;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Bar ${page + 1}',
                        style: const TextStyle(color: StudioColors.textDim),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          for (var pad = 0; pad < names.length; pad++)
                            _PadRow(
                              label: names[pad],
                              track: track,
                              padIndex: pad,
                              offset: offset,
                              steps: steps,
                              playhead: c.playheadStep,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PadRow extends StatelessWidget {
  const _PadRow({
    required this.label,
    required this.track,
    required this.padIndex,
    required this.offset,
    required this.steps,
    required this.playhead,
  });

  final String label;
  final Track track;
  final int padIndex;
  final int offset;
  final int steps;
  final int playhead;

  @override
  Widget build(BuildContext context) {
    final c = context.read<StudioController>();
    final trackColor = StudioColors.forTrack(track);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: trackColor.withValues(alpha: 0.85),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (var s = 0; s < steps; s++)
            Builder(builder: (context) {
              final step = offset + s;
              final on = c.isStepOn(track, padIndex, step);
              final isPlay = playhead == step;
              final beat = s % 4 == 0;
              final vel = on ? c.stepVelocity(track, padIndex, step) : 0;
              final prob = on ? c.stepProbability(track, padIndex, step) : 100;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => c.setStepCell(
                    trackId: track.id,
                    padIndex: padIndex,
                    step: step,
                    on: !on,
                  ),
                  onLongPress: on
                      ? () => _editStepParams(
                            context,
                            c,
                            step: step,
                            velocity: vel,
                            probability: prob,
                          )
                      : null,
                  child: _VelocityStep(
                    on: on,
                    velocity: vel,
                    probability: prob,
                    isPlay: isPlay,
                    beat: beat,
                    color: trackColor,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _editStepParams(
    BuildContext context,
    StudioController c, {
    required int step,
    required int velocity,
    required int probability,
  }) async {
    var vel = velocity.toDouble();
    var prob = probability.toDouble();
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Step params'),
          content: StatefulBuilder(
            builder: (ctx, setSt) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Velocity ${vel.round()}'),
                Slider(
                  min: 1,
                  max: 127,
                  value: vel,
                  onChanged: (x) => setSt(() => vel = x),
                ),
                Text('Probability ${prob.round()}%'),
                Slider(
                  min: 0,
                  max: 100,
                  divisions: 20,
                  value: prob,
                  onChanged: (x) => setSt(() => prob = x),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, (vel.round(), prob.round())),
              child: const Text('Set'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    c.setStepVelocity(
      trackId: track.id,
      padIndex: padIndex,
      step: step,
      velocity: result.$1,
    );
    c.setStepProbability(
      trackId: track.id,
      padIndex: padIndex,
      step: step,
      probability: result.$2,
    );
  }
}

/// Solid luminous fill; height + intensity map to step velocity.
class _VelocityStep extends StatelessWidget {
  const _VelocityStep({
    required this.on,
    required this.velocity,
    required this.probability,
    required this.isPlay,
    required this.beat,
    required this.color,
  });

  final bool on;
  final int velocity;
  final int probability;
  final bool isPlay;
  final bool beat;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const w = 28.0;
    const h = 36.0;
    final velT = (velocity / 127.0).clamp(0.0, 1.0);
    final fillH = on ? (10.0 + velT * (h - 10.0)) : 0.0;
    final alpha = on ? (0.45 + velT * 0.55).clamp(0.45, 1.0) : 0.0;
    final dimForProb = on ? (probability / 100.0).clamp(0.35, 1.0) : 1.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: beat ? StudioColors.surface2 : StudioColors.bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isPlay
              ? StudioColors.play
              : (on ? color.withValues(alpha: 0.55) : StudioColors.border),
          width: isPlay ? 2 : 1,
        ),
        boxShadow: on
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35 * velT),
                  blurRadius: 6 + 6 * velT,
                  spreadRadius: 0.2,
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          if (on)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: w,
                height: fillH,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      color.withValues(alpha: alpha * dimForProb),
                      color.withValues(alpha: (alpha * 0.75) * dimForProb),
                    ],
                  ),
                ),
              ),
            ),
          if (on && probability < 100)
            Positioned(
              top: 2,
              child: Text(
                '$probability',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: StudioColors.text.withValues(alpha: 0.85),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


class _PatternPill extends StatelessWidget {
  const _PatternPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : StudioColors.surface2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : StudioColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? StudioColors.bg : StudioColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}
