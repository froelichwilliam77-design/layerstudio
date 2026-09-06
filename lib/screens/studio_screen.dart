import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../widgets/arrange_view.dart';
import '../widgets/drum_pads.dart';
import '../widgets/empty_state.dart';
import '../widgets/guitar_chords.dart';
import '../widgets/piano_roll.dart';
import '../widgets/step_sequencer.dart';
import '../widgets/touch_keyboard.dart';
import '../widgets/track_rail.dart';
import '../widgets/transport_bar.dart';
import 'mixer_screen.dart';
import 'sound_library_screen.dart';

class StudioScreen extends StatelessWidget {
  const StudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project;
    if (p == null) {
      return const Scaffold(body: Center(child: Text('No project')));
    }

    final onBeatSurface = _isBeatSurface(c.tab);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            tooltip: 'Export project (.layerstudio)',
            onPressed: () async {
              final err = await c.exportProjectBundle();
              if (context.mounted && err != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Project export failed: $err')),
                );
              }
            },
            icon: const Icon(Icons.folder_zip_outlined),
          ),
          IconButton(
            tooltip: 'Save',
            onPressed: () async {
              await c.saveNow();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved')),
                );
              }
            },
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          // Track hierarchy only where you pick what to edit (phone IA).
          if (onBeatSurface) TrackRail(controller: c),
          if (onBeatSurface)
            const Divider(height: 1, color: StudioColors.border),
          Expanded(child: _body(c)),
          const TransportBar(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 64,
        backgroundColor: StudioColors.surface,
        indicatorColor: StudioColors.accent.withValues(alpha: 0.25),
        selectedIndex: _indexFor(c.tab),
        onDestinationSelected: (i) {
          if (i == 2) {
            _openBeatSurface(c);
          } else {
            c.setTab(_tabFor(i));
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.view_timeline_outlined),
            selectedIcon: Icon(Icons.view_timeline),
            label: 'Arrange',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Sounds',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_on_outlined),
            selectedIcon: Icon(Icons.grid_on),
            label: 'Beat',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Mixer',
          ),
        ],
      ),
    );
  }

  bool _isBeatSurface(StudioTab tab) => switch (tab) {
        StudioTab.drums ||
        StudioTab.piano ||
        StudioTab.keys ||
        StudioTab.guitar =>
          true,
        _ => false,
      };

  /// Prefer drums as the primary Beat destination; keep current layer if already editing one.
  void _openBeatSurface(StudioController c) {
    final tracks = c.project?.tracks ?? [];
    final selected = c.selectedTrack;
    if (selected != null &&
        (selected.category.isBeatPrimary ||
            selected.category == TrackCategory.bass ||
            selected.category == TrackCategory.guitar ||
            selected.category == TrackCategory.keys)) {
      c.selectTrack(selected.id);
      return;
    }
    final drums = tracks.where((t) => t.category == TrackCategory.drums);
    if (drums.isNotEmpty) {
      c.selectTrack(drums.first.id);
      return;
    }
    final layer = tracks.where((t) => t.category.isLayer);
    if (layer.isNotEmpty) {
      c.selectTrack(layer.first.id);
      return;
    }
    c.setTab(StudioTab.library);
  }

  int _indexFor(StudioTab tab) {
    return switch (tab) {
      StudioTab.arrange => 0,
      StudioTab.library => 1,
      StudioTab.mixer => 3,
      _ => 2,
    };
  }

  StudioTab _tabFor(int i) {
    return switch (i) {
      0 => StudioTab.arrange,
      1 => StudioTab.library,
      3 => StudioTab.mixer,
      _ => StudioTab.drums,
    };
  }

  Widget _body(StudioController c) {
    switch (c.tab) {
      case StudioTab.arrange:
        return const ArrangeView();
      case StudioTab.library:
        return const SoundLibraryScreen();
      case StudioTab.mixer:
        return const MixerScreen();
      case StudioTab.drums:
      case StudioTab.piano:
      case StudioTab.keys:
      case StudioTab.guitar:
        return _Editor(c: c);
    }
  }
}

class _Editor extends StatelessWidget {
  const _Editor({required this.c});
  final StudioController c;

  @override
  Widget build(BuildContext context) {
    final track = c.selectedTrack;
    if (track == null) {
      return EmptyState(
        icon: Icons.grid_on,
        title: 'Start with drums',
        subtitle:
            'Open Sounds, add a drum kit, then program pads or the step sequencer. Layer bass, guitar, and keys after the beat.',
        actionLabel: 'Sound Library',
        onAction: () => c.setTab(StudioTab.library),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorHeader(track: track),
        _ModeBar(c: c, track: track),
        Expanded(child: _editorBody(track)),
      ],
    );
  }

  Widget _editorBody(Track track) {
    if (track.category == TrackCategory.drums) {
      if (track.effectiveMode == TrackInstrumentMode.drumPads) {
        return DrumPads(track: track);
      }
      return StepSequencer(track: track);
    }
    if (track.category == TrackCategory.keys && c.tab == StudioTab.keys) {
      return TouchKeyboard(track: track);
    }
    if (track.category == TrackCategory.guitar && c.tab == StudioTab.guitar) {
      return GuitarChordStrips(track: track);
    }
    // Bass (and keys/guitar piano-roll mode)
    return PianoRoll(track: track);
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final color = Color(track.colorValue);
    final isDrums = track.category.isBeatPrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.55)),
            ),
            child: Text(
              isDrums ? 'BEAT · DRUMS' : 'LAYER · ${track.category.shortLabel.toUpperCase()}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeBar extends StatelessWidget {
  const _ModeBar({required this.c, required this.track});
  final StudioController c;
  final Track track;

  @override
  Widget build(BuildContext context) {
    if (track.category == TrackCategory.drums) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: _ModeChip(
                label: 'Pads',
                selected: track.effectiveMode == TrackInstrumentMode.drumPads,
                onTap: () {
                  c.setTrackInstrumentMode(track, TrackInstrumentMode.drumPads);
                  c.setTab(StudioTab.drums);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ModeChip(
                label: 'Step Seq',
                selected: track.effectiveMode == TrackInstrumentMode.stepSeq,
                onTap: () {
                  c.setTrackInstrumentMode(track, TrackInstrumentMode.stepSeq);
                  c.setTab(StudioTab.drums);
                },
              ),
            ),
          ],
        ),
      );
    }

    if (track.category == TrackCategory.bass ||
        track.category == TrackCategory.mic) {
      // Single primary editor — no cluttered mode strip.
      return const SizedBox(height: 4);
    }

    if (track.category == TrackCategory.keys) {
      final onKeyboard = c.tab == StudioTab.keys;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: _ModeChip(
                label: 'Piano Roll',
                selected: !onKeyboard,
                onTap: () {
                  c.setTrackInstrumentMode(track, TrackInstrumentMode.pianoRoll);
                  c.setTab(StudioTab.piano);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ModeChip(
                label: 'Keyboard',
                selected: onKeyboard,
                onTap: () {
                  c.setTrackInstrumentMode(track, TrackInstrumentMode.keyboard);
                  c.setTab(StudioTab.keys);
                },
              ),
            ),
          ],
        ),
      );
    }

    if (track.category == TrackCategory.guitar) {
      final onChords = c.tab == StudioTab.guitar;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Row(
          children: [
            Expanded(
              child: _ModeChip(
                label: 'Piano Roll',
                selected: !onChords,
                onTap: () {
                  c.setTrackInstrumentMode(track, TrackInstrumentMode.pianoRoll);
                  c.setTab(StudioTab.piano);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ModeChip(
                label: 'Chords',
                selected: onChords,
                onTap: () {
                  c.setTrackInstrumentMode(
                      track, TrackInstrumentMode.guitarChords);
                  c.setTab(StudioTab.guitar);
                },
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? StudioColors.accent.withValues(alpha: 0.28)
          : StudioColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? StudioColors.accent : StudioColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
