import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

/// Phone-first track selector: drums as primary beat surface, melodic as layers.
class TrackRail extends StatelessWidget {
  const TrackRail({super.key, required this.controller});

  final StudioController controller;

  IconData _iconFor(TrackCategory cat) => switch (cat) {
        TrackCategory.drums => Icons.grid_view_rounded,
        TrackCategory.bass => Icons.graphic_eq,
        TrackCategory.guitar => Icons.music_note,
        TrackCategory.keys => Icons.piano,
        TrackCategory.mic => Icons.mic,
      };

  @override
  Widget build(BuildContext context) {
    final tracks = controller.project?.tracks ?? [];
    if (tracks.isEmpty) return const SizedBox.shrink();

    final drums = tracks.where((t) => t.category == TrackCategory.drums).toList();
    final layers = tracks
        .where((t) =>
            t.category == TrackCategory.bass ||
            t.category == TrackCategory.guitar ||
            t.category == TrackCategory.keys)
        .toList();

    return Material(
      color: StudioColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionLabel('BEAT', accent: StudioColors.accent2),
            const SizedBox(height: 6),
            if (drums.isEmpty)
              _emptyHint(
                'Add a drum kit in Sounds — pads & step seq live here.',
              )
            else
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: drums.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => _DrumCard(
                    track: drums[i],
                    selected: drums[i].id == controller.selectedTrackId,
                    onTap: () => controller.selectTrack(drums[i].id),
                    icon: _iconFor(TrackCategory.drums),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _sectionLabel('LAYERS', accent: StudioColors.textDim),
                ),
                Text(
                  'Bass · Guitar · Keys',
                  style: TextStyle(
                    fontSize: 10,
                    color: StudioColors.textDim.withValues(alpha: 0.85),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (layers.isEmpty)
              _emptyHint('Layer bass, guitar, or keys when the groove is set.')
            else
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: layers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final t = layers[i];
                    final selected = t.id == controller.selectedTrackId;
                    return _LayerChip(
                      track: t,
                      selected: selected,
                      icon: _iconFor(t.category),
                      onTap: () => controller.selectTrack(t.id),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, {required Color accent}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        color: accent,
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: StudioColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: StudioColors.textDim),
      ),
    );
  }
}

class _DrumCard extends StatelessWidget {
  const _DrumCard({
    required this.track,
    required this.selected,
    required this.onTap,
    required this.icon,
  });

  final Track track;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Color(track.colorValue);
    return Material(
      color: selected
          ? color.withValues(alpha: 0.28)
          : StudioColors.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minWidth: 168),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? color : StudioColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: StudioColors.text),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'DRUMS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: StudioColors.accent2,
                      ),
                    ),
                    Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LayerChip extends StatelessWidget {
  const _LayerChip({
    required this.track,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final Track track;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(track.colorValue);
    return FilterChip(
      avatar: Icon(icon, size: 16, color: StudioColors.text),
      label: Text(
        '${track.category.shortLabel} · ${track.name}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: color.withValues(alpha: 0.32),
      backgroundColor: StudioColors.surface2,
      side: BorderSide(
        color: selected ? color : StudioColors.border,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
