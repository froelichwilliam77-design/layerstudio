import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/pattern.dart';
import '../models/track.dart';
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
        subtitle:
            'Beat-maker first: add a drum kit, program a groove, then layer bass/keys.',
        actionLabel: 'Open Sound Library',
        onAction: () => c.setTab(StudioTab.library),
      );
    }

    final steps = p.songMode
        ? (p.arrangementEndBar * p.stepsPerBar).clamp(16, 512)
        : p.loopEndStep.clamp(16, 256);
    const cellW = 10.0;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _PatternBank(c: c),
        const SizedBox(height: 8),
        _SongArrange(c: c),
        const SizedBox(height: 12),
        for (final t in p.tracks)
          _TrackLane(
            track: t,
            selected: t.id == c.selectedTrackId,
            playhead: c.playheadStep,
            steps: steps,
            cellW: cellW,
            onSelect: () => c.selectTrack(t.id),
            onDelete: () => c.removeTrack(t.id),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await c.addMicTrack();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Mic track added. Arm ● then Play to record from the playhead.',
                  ),
                ),
              );
            }
          },
          icon: const Icon(Icons.mic_none),
          label: const Text('Add mic track'),
        ),
      ],
    );
  }
}

class _PatternBank extends StatelessWidget {
  const _PatternBank({required this.c});
  final StudioController c;

  @override
  Widget build(BuildContext context) {
    final p = c.project!;
    return Card(
      color: StudioColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Patterns', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (var i = 0; i < p.patterns.length; i++)
                  ChoiceChip(
                    label: Text(p.patterns[i].name),
                    selected: p.activePatternIndex == i,
                    onSelected: (_) => c.selectPattern(i),
                  ),
                ActionChip(
                  label: const Text('Copy → next'),
                  onPressed: () {
                    final to = (p.activePatternIndex + 1) % p.patterns.length;
                    c.copyPattern(fromIndex: p.activePatternIndex, toIndex: to);
                  },
                ),
                ActionChip(
                  label: const Text('Clear'),
                  onPressed: () => c.clearPattern(p.activePatternIndex),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SongArrange extends StatelessWidget {
  const _SongArrange({required this.c});
  final StudioController c;

  @override
  Widget build(BuildContext context) {
    final p = c.project!;
    final endBar = (p.arrangementEndBar < 8 ? 8 : p.arrangementEndBar + 2)
        .clamp(8, 64);
    const barW = 36.0;

    return Card(
      color: StudioColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Song arrange',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                FilterChip(
                  label: Text(p.songMode ? 'Song mode ON' : 'Pattern mode'),
                  selected: p.songMode,
                  onSelected: (v) => c.updateProjectMeta(songMode: v),
                ),
                const SizedBox(width: 6),
                FilledButton.tonal(
                  onPressed: () => c.addArrangementClip(),
                  child: const Text('Add clip'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (p.arrangement.isEmpty)
              const Text(
                'Add pattern clips, then drag to move, tap to pick a pattern, or use +/− to resize. Enable Song mode to play them in order.',
                style: TextStyle(fontSize: 12, color: StudioColors.textDim),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: endBar * barW + 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (var b = 0; b < endBar; b++)
                            SizedBox(
                              width: barW,
                              child: Text(
                                '${b + 1}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: StudioColors.textDim,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...p.arrangement.map((clip) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _ClipBlock(
                            c: c,
                            clip: clip,
                            barW: barW,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClipBlock extends StatelessWidget {
  const _ClipBlock({
    required this.c,
    required this.clip,
    required this.barW,
  });

  final StudioController c;
  final ArrangementClip clip;
  final double barW;

  @override
  Widget build(BuildContext context) {
    final name = c.patternById(clip.patternId)?.name ?? '?';
    return GestureDetector(
      onHorizontalDragStart: (_) => c.beginGestureUndo(),
      onHorizontalDragUpdate: (d) {
        final deltaBars = (d.delta.dx / barW).round();
        if (deltaBars == 0) return;
        c.moveArrangementClip(clip.id, clip.startBar + deltaBars);
      },
      onHorizontalDragEnd: (_) => c.endGestureUndo('Move clip'),
      child: Row(
        children: [
          SizedBox(width: clip.startBar * barW),
          Container(
            width: (clip.lengthBars * barW).clamp(barW, 800),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: StudioColors.accent.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: StudioColors.accent),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name · ${clip.lengthBars} bar${clip.lengthBars == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _pickPattern(context),
                      child: const Padding(
                        padding: EdgeInsets.only(right: 6, top: 2),
                        child: Text('Pattern',
                            style: TextStyle(
                                fontSize: 10, color: StudioColors.accent2)),
                      ),
                    ),
                    InkWell(
                      onTap: () => c.resizeArrangementClip(
                        clip.id,
                        clip.lengthBars - 1,
                      ),
                      child: const Text('−', style: TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => c.resizeArrangementClip(
                        clip.id,
                        clip.lengthBars + 1,
                      ),
                      child: const Text('+', style: TextStyle(fontSize: 16)),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => c.duplicateArrangementClip(clip.id),
                      child: const Icon(Icons.copy, size: 14),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => c.removeArrangementClip(clip.id),
                      child: const Icon(Icons.close, size: 14),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPattern(BuildContext context) async {
    final p = c.project!;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: StudioColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Clip pattern')),
            for (final pat in p.patterns)
              ListTile(
                title: Text(pat.name),
                selected: pat.id == clip.patternId,
                onTap: () => Navigator.pop(ctx, pat.id),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) c.setArrangementClipPattern(clip.id, chosen);
  }
}

class _TrackLane extends StatelessWidget {
  const _TrackLane({
    required this.track,
    required this.selected,
    required this.playhead,
    required this.steps,
    required this.cellW,
    required this.onSelect,
    required this.onDelete,
  });

  final Track track;
  final bool selected;
  final int playhead;
  final int steps;
  final double cellW;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.read<StudioController>();
    return GestureDetector(
      onTap: onSelect,
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
                    color: Color(track.colorValue),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    track.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (track.category == TrackCategory.mic) ...[
                  IconButton(
                    tooltip: track.recordArmed ? 'Disarm' : 'Arm record',
                    onPressed: () =>
                        c.armMicTrack(track.id, !track.recordArmed),
                    icon: Icon(
                      track.recordArmed ? Icons.fiber_manual_record : Icons.fiber_manual_record_outlined,
                      color: track.recordArmed
                          ? StudioColors.danger
                          : StudioColors.textDim,
                      size: 18,
                    ),
                  ),
                  if (track.recordedFilePath != null)
                    const Icon(Icons.check_circle,
                        size: 16, color: StudioColors.play),
                ],
                Text(
                  track.category.name.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: StudioColors.textDim,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: onDelete,
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
                    notes: track.notes.map((n) => n.startStep).toList(),
                    color: Color(track.colorValue),
                    playhead: playhead,
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
