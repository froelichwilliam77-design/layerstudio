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
          _TrackChips(c: c),
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
          c.setTab(_tabFor(i, c));
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
            label: 'Edit',
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

  int _indexFor(StudioTab tab) {
    return switch (tab) {
      StudioTab.arrange => 0,
      StudioTab.library => 1,
      StudioTab.mixer => 3,
      _ => 2,
    };
  }

  StudioTab _tabFor(int i, StudioController c) {
    return switch (i) {
      0 => StudioTab.arrange,
      1 => StudioTab.library,
      3 => StudioTab.mixer,
      _ => _editTabFor(c),
    };
  }

  StudioTab _editTabFor(StudioController c) {
    final t = c.selectedTrack;
    if (t == null) return StudioTab.library;
    return switch (t.category) {
      TrackCategory.drums => StudioTab.drums,
      TrackCategory.bass => StudioTab.piano,
      TrackCategory.guitar => StudioTab.guitar,
      TrackCategory.keys => StudioTab.keys,
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

class _TrackChips extends StatelessWidget {
  const _TrackChips({required this.c});
  final StudioController c;

  @override
  Widget build(BuildContext context) {
    final tracks = c.project?.tracks ?? [];
    if (tracks.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = tracks[i];
          final selected = t.id == c.selectedTrackId;
          return ChoiceChip(
            label: Text(t.name),
            selected: selected,
            onSelected: (_) => c.selectTrack(t.id),
            selectedColor: Color(t.colorValue).withValues(alpha: 0.35),
          );
        },
      ),
    );
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
        icon: Icons.music_note,
        title: 'Add drums',
        subtitle: 'Open the Sound Library and add a drum kit or instrument.',
        actionLabel: 'Sound Library',
        onAction: () => c.setTab(StudioTab.library),
      );
    }

    // Mode switcher for drums / melodic
    return Column(
      children: [
        if (track.category == TrackCategory.drums)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Pads'),
                  selected: c.tab == StudioTab.drums &&
                      track.effectiveMode == TrackInstrumentMode.drumPads,
                  onSelected: (_) {
                    c.setTrackInstrumentMode(track, TrackInstrumentMode.drumPads);
                    c.setTab(StudioTab.drums);
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Step Seq'),
                  selected: track.effectiveMode == TrackInstrumentMode.stepSeq,
                  onSelected: (_) {
                    c.setTrackInstrumentMode(track, TrackInstrumentMode.stepSeq);
                    c.setTab(StudioTab.drums);
                  },
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Piano Roll'),
                  selected: true,
                  onSelected: (_) {},
                ),
                const SizedBox(width: 8),
                if (track.category == TrackCategory.keys)
                  ChoiceChip(
                    label: const Text('Keyboard'),
                    selected: c.tab == StudioTab.keys,
                    onSelected: (_) => c.setTab(StudioTab.keys),
                  ),
                if (track.category == TrackCategory.guitar)
                  ChoiceChip(
                    label: const Text('Chords'),
                    selected: c.tab == StudioTab.guitar,
                    onSelected: (_) => c.setTab(StudioTab.guitar),
                  ),
              ],
            ),
          ),
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
    if (c.tab == StudioTab.keys ||
        track.effectiveMode == TrackInstrumentMode.keyboard) {
      if (track.category == TrackCategory.keys && c.tab == StudioTab.keys) {
        return TouchKeyboard(track: track);
      }
    }
    if (c.tab == StudioTab.guitar ||
        track.category == TrackCategory.guitar &&
            track.effectiveMode == TrackInstrumentMode.guitarChords) {
      if (track.category == TrackCategory.guitar) {
        // Show chords when guitar tab; else piano roll
        if (c.tab == StudioTab.guitar) {
          return GuitarChordStrips(track: track);
        }
      }
    }
    // Default melodic editor
    if (track.category == TrackCategory.keys && c.tab == StudioTab.keys) {
      return TouchKeyboard(track: track);
    }
    if (track.category == TrackCategory.guitar && c.tab == StudioTab.guitar) {
      return GuitarChordStrips(track: track);
    }
    return PianoRoll(track: track);
  }
}
