import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../utils/music_theory.dart';

class GuitarChordStrips extends StatelessWidget {
  const GuitarChordStrips({super.key, required this.track});

  final Track track;

  static const chords = [
    ('C', false),
    ('Dm', true),
    ('Em', true),
    ('F', false),
    ('G', false),
    ('Am', true),
    ('Bdim', true),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project!;
    // Map relative to project key
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

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: 7,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final pc = (rootPc + offsets[i]) % 12;
        final rootMidi = 48 + pc; // around C3
        final name = '${MusicTheory.pitchNames[pc]}${minors[i] ? 'm' : ''}';
        return Material(
          color: Color(track.colorValue).withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final notes = MusicTheory.triad(rootMidi, minor: minors[i]);
              for (final n in notes) {
                await c.triggerNote(track, n, velocity: 0.85);
              }
              if (c.isPlaying) {
                for (final n in notes) {
                  c.addOrToggleNote(
                    trackId: track.id,
                    pitch: n,
                    startStep: c.playheadStep,
                    lengthSteps: 4,
                  );
                }
              }
            },
            child: Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: StudioColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: StudioColors.surface2,
                    child: Text(labels[i],
                        style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.music_note, color: StudioColors.textDim),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
