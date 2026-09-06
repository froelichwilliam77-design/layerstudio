import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../utils/music_theory.dart';

class TouchKeyboard extends StatefulWidget {
  const TouchKeyboard({super.key, required this.track});

  final Track track;

  @override
  State<TouchKeyboard> createState() => _TouchKeyboardState();
}

class _TouchKeyboardState extends State<TouchKeyboard> {
  int octave = 4;

  static const whites = [0, 2, 4, 5, 7, 9, 11];
  static const blacks = [1, 3, -1, 6, 8, 10]; // -1 = gap

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project!;
    final base = (octave + 1) * 12;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => octave = (octave - 1).clamp(1, 6)),
                icon: const Icon(Icons.keyboard_arrow_down),
              ),
              Text('Octave $octave',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              IconButton(
                onPressed: () => setState(() => octave = (octave + 1).clamp(1, 6)),
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
              const Spacer(),
              const Text('Tap to play · hold playhead to record',
                  style: TextStyle(fontSize: 11, color: StudioColors.textDim)),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final whiteW = box.maxWidth / 7;
            return Stack(
              children: [
                Row(
                  children: [
                    for (final pc in whites)
                      _Key(
                        width: whiteW,
                        label: MusicTheory.noteName(base + pc),
                        isBlack: false,
                        highlight: MusicTheory.inScale(base + pc, p.key, p.scale),
                        onTap: () => _hit(c, base + pc),
                      ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: box.maxHeight * 0.58,
                  child: Row(
                    children: [
                      SizedBox(width: whiteW * 0.65),
                      for (var i = 0; i < blacks.length; i++) ...[
                        if (blacks[i] < 0)
                          SizedBox(width: whiteW)
                        else
                          _Key(
                            width: whiteW * 0.7,
                            label: '',
                            isBlack: true,
                            highlight: MusicTheory.inScale(
                                base + blacks[i], p.key, p.scale),
                            onTap: () => _hit(c, base + blacks[i]),
                          ),
                        if (blacks[i] >= 0) SizedBox(width: whiteW * 0.3),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  void _hit(StudioController c, int midi) {
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

class _Key extends StatelessWidget {
  const _Key({
    required this.width,
    required this.label,
    required this.isBlack,
    required this.highlight,
    required this.onTap,
  });

  final double width;
  final String label;
  final bool isBlack;
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isBlack
          ? (highlight ? const Color(0xFF3A4158) : const Color(0xFF10131A))
          : (highlight ? const Color(0xFF2A3348) : const Color(0xFF1A1F2B)),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            border: Border.all(color: StudioColors.border),
          ),
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isBlack ? StudioColors.textDim : StudioColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
