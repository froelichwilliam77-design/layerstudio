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
    final steps = 16; // one bar view, scrollable for more
    final pages = (p.loopEndStep / steps).ceil().clamp(1, 8);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              const Text('16-step', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: () => c.clearTrackNotes(track.id),
                child: const Text('Clear'),
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
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => c.setStepCell(
                    trackId: track.id,
                    padIndex: padIndex,
                    step: step,
                    on: !on,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: on
                          ? Color(track.colorValue)
                          : (beat
                              ? StudioColors.surface2
                              : StudioColors.bg),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isPlay
                            ? StudioColors.play
                            : StudioColors.border,
                        width: isPlay ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
