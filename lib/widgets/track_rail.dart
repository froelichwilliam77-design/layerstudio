import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

/// Compact single-row track nav. Secondary track/settings live in an expandable panel.
class TrackRail extends StatefulWidget {
  const TrackRail({super.key, required this.controller});

  final StudioController controller;

  @override
  State<TrackRail> createState() => _TrackRailState();
}

class _TrackRailState extends State<TrackRail> {
  bool _expanded = false;

  IconData _iconFor(TrackCategory cat) => switch (cat) {
        TrackCategory.drums => Icons.grid_view_rounded,
        TrackCategory.bass => Icons.graphic_eq,
        TrackCategory.guitar => Icons.music_note,
        TrackCategory.keys => Icons.piano,
        TrackCategory.mic => Icons.mic,
      };

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tracks = controller.project?.tracks ?? [];
    if (tracks.isEmpty) return const SizedBox.shrink();

    final drums =
        tracks.where((t) => t.category == TrackCategory.drums).toList();
    final layers = tracks
        .where((t) =>
            t.category == TrackCategory.bass ||
            t.category == TrackCategory.guitar ||
            t.category == TrackCategory.keys ||
            t.category == TrackCategory.mic)
        .toList();
    final ordered = [...drums, ...layers];
    final selected = controller.selectedTrack;

    return Material(
      color: StudioColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    itemCount: ordered.isEmpty ? 1 : ordered.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      if (ordered.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: StudioColors.surface2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: StudioColors.border),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Add drums in Sounds',
                            style: TextStyle(
                                fontSize: 12, color: StudioColors.textDim),
                          ),
                        );
                      }
                      final t = ordered[i];
                      final isSelected = t.id == controller.selectedTrackId;
                      final color = StudioColors.forTrack(t);
                      final isLayer = t.category.isLayer;
                      return Material(
                        color: isSelected
                            ? color.withValues(alpha: 0.30)
                            : StudioColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => controller.selectTrack(t.id),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    isSelected ? color : StudioColors.border,
                                width: isSelected ? 1.5 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: color.withValues(alpha: 0.35),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withValues(alpha: 0.7),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(_iconFor(t.category),
                                    size: 16, color: color),
                                const SizedBox(width: 6),
                                Text(
                                  t.category == TrackCategory.drums
                                      ? t.name
                                      : '${t.category.shortLabel} · ${t.name}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: isLayer && !isSelected
                                        ? StudioColors.textDim
                                        : StudioColors.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: _expanded ? 'Collapse' : 'Track settings',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.tune_rounded,
                    color: _expanded
                        ? StudioColors.accent
                        : StudioColors.textDim,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: StudioColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'TRACK · SETTINGS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: selected != null
                          ? StudioColors.forTrack(selected)
                          : StudioColors.textDim,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    drums.isEmpty
                        ? 'Add a drum kit in Sounds — pads & step seq live on Beat.'
                        : layers.isEmpty
                            ? 'Layer bass, guitar, or keys when the groove is set.'
                            : 'Beat kits first; layers after. Colors carry into modes & steps.',
                    style: const TextStyle(
                        fontSize: 12, color: StudioColors.textDim),
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _MiniToggle(
                          label: 'Mute',
                          active: selected.muted,
                          color: StudioColors.danger,
                          onTap: () {
                            selected.muted = !selected.muted;
                            controller.updateTrack(selected);
                          },
                        ),
                        const SizedBox(width: 8),
                        _MiniToggle(
                          label: 'Solo',
                          active: selected.solo,
                          color: StudioColors.warning,
                          onTap: () {
                            selected.solo = !selected.solo;
                            controller.updateTrack(selected);
                          },
                        ),
                        const Spacer(),
                        Text(
                          selected.category.shortLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: StudioColors.forTrack(selected),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? color.withValues(alpha: 0.28) : StudioColors.surface2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? color : StudioColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? color : StudioColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}
