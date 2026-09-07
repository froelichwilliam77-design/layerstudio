import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/sound_library.dart';
import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

class DrumPads extends StatelessWidget {
  const DrumPads({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final preset = SoundLibrary.byId(track.presetId);
    final kit = preset?.drumKit;
    if (kit == null) {
      return const Center(child: Text('Not a drum kit'));
    }
    final names = kit.keys.toList();
    final c = context.read<StudioController>();
    final color = StudioColors.forTrack(track);

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.15,
      ),
      itemCount: names.length,
      itemBuilder: (context, i) {
        return Material(
          color: color.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTapDown: (_) {
              HapticFeedback.mediumImpact();
              c.triggerPad(track, i);
              if (!c.eraseMode) {
                c.setStepCell(
                  trackId: track.id,
                  padIndex: i,
                  step:
                      c.playheadStep %
                      (c.project?.loopEndStep ?? 16).clamp(1, 9999),
                  on: true,
                );
              }
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.65)),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.22),
                    blurRadius: 10,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                names[i],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
