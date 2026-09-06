import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import 'empty_state.dart';

class ArrangeView extends StatelessWidget {
  const ArrangeView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project!;
    if (p.tracks.isEmpty) {
      return EmptyState(
        icon: Icons.layers_outlined,
        title: 'Stack your first layer',
        subtitle: 'Add drums, bass, guitar, or keys from the Sound Library.',
        actionLabel: 'Open Sound Library',
        onAction: () => c.setTab(StudioTab.library),
      );
    }

    final steps = p.loopEndStep.clamp(16, 256);
    const cellW = 10.0;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: p.tracks.length,
      itemBuilder: (context, i) {
        final t = p.tracks[i];
        final selected = t.id == c.selectedTrackId;
        return GestureDetector(
          onTap: () => c.selectTrack(t.id),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: StudioColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? StudioColors.accent : StudioColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Color(t.colorValue),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      t.category.name.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: StudioColors.textDim,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => c.removeTrack(t.id),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    height: 36,
                    width: steps * cellW,
                    child: CustomPaint(
                      painter: _ClipPainter(
                        notes: t.notes.map((n) => n.startStep).toList(),
                        color: Color(t.colorValue),
                        playhead: c.playheadStep,
                        steps: steps,
                        cellW: cellW,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClipPainter extends CustomPainter {
  _ClipPainter({
    required this.notes,
    required this.color,
    required this.playhead,
    required this.steps,
    required this.cellW,
  });

  final List<int> notes;
  final Color color;
  final int playhead;
  final int steps;
  final double cellW;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = StudioColors.surface2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      bg,
    );
    final notePaint = Paint()..color = color.withValues(alpha: 0.85);
    for (final s in notes) {
      if (s < 0 || s >= steps) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(s * cellW, 6, cellW * 0.9, size.height - 12),
          const Radius.circular(2),
        ),
        notePaint,
      );
    }
    final ph = Paint()
      ..color = StudioColors.play
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(playhead * cellW, 0),
      Offset(playhead * cellW, size.height),
      ph,
    );
  }

  @override
  bool shouldRepaint(covariant _ClipPainter old) =>
      old.playhead != playhead || old.notes.length != notes.length;
}
