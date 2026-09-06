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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              const Text('16-step', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              ...List.generate(p.patterns.length, (i) {
                final selected = p.activePatternIndex == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    label: Text(p.patterns[i].name,
                        style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) => c.selectPattern(i),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }),
              const Spacer(),
              Text('Prob ${c.drawProbability}%',
                  style: const TextStyle(
                      fontSize: 11, color: StudioColors.textDim)),
              SizedBox(
                width: 80,
                child: Slider(
                  min: 0,
                  max: 100,
                  divisions: 20,
                  value: c.drawProbability.toDouble(),
                  onChanged: (v) => c.setDrawProbability(v.round()),
                ),
              ),
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
                      value: 'clear_track', child: Text('Clear track (pattern)')),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: StudioColors.textDim),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (var s = 0; s < steps; s++)
            Builder(builder: (context) {
              final step = offset + s;
              final on = c.isStepOn(track, padIndex, step);
              final isPlay = playhead == step;
              final beat = s % 4 == 0;
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
                      ? () async {
                          final v = await showDialog<int>(
                            context: context,
                            builder: (ctx) {
                              var val = prob.toDouble();
                              return AlertDialog(
                                title: const Text('Step probability'),
                                content: StatefulBuilder(
                                  builder: (ctx, setSt) => Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('${val.round()}%'),
                                      Slider(
                                        min: 0,
                                        max: 100,
                                        divisions: 20,
                                        value: val,
                                        onChanged: (x) =>
                                            setSt(() => val = x),
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
                                    onPressed: () =>
                                        Navigator.pop(ctx, val.round()),
                                    child: const Text('Set'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (v != null) {
                            c.setStepProbability(
                              trackId: track.id,
                              padIndex: padIndex,
                              step: step,
                              probability: v,
                            );
                          }
                        }
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on
                          ? Color(track.colorValue)
                              .withValues(alpha: (prob / 100).clamp(0.25, 1))
                          : (beat ? StudioColors.surface2 : StudioColors.bg),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color:
                            isPlay ? StudioColors.play : StudioColors.border,
                        width: isPlay ? 2 : 1,
                      ),
                    ),
                    child: on && prob < 100
                        ? Text(
                            '$prob',
                            style: const TextStyle(fontSize: 8),
                          )
                        : null,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
