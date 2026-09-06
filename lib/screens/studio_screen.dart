import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../widgets/arrange_view.dart';
import '../widgets/drum_pads.dart';
import '../widgets/empty_state.dart';
import '../widgets/fretboard.dart';
import '../widgets/mode_segment.dart';
import '../widgets/piano_roll.dart';
import '../widgets/step_sequencer.dart';
import '../widgets/strum_bars.dart';
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

    final accent = Color(track.colorValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StudioNavBar(c: c, track: track, accent: accent),
        Expanded(child: _editorBody(track)),
      ],
    );
  }

  Widget _editorBody(Track track) {
    final mode = track.effectiveMode;
    return switch (mode) {
      TrackInstrumentMode.drumPads => DrumPads(track: track),
      TrackInstrumentMode.stepSeq => StepSequencer(track: track),
      TrackInstrumentMode.fretboard => BassFretboard(track: track),
      TrackInstrumentMode.guitarChords => StrumBars(track: track),
      TrackInstrumentMode.keyboard => TouchKeyboard(track: track),
      TrackInstrumentMode.pianoRoll => PianoRoll(track: track),
      TrackInstrumentMode.micRecord => const Center(
          child: Text('Arm mic from Mixer / Arrange'),
        ),
    };
  }
}

class _StudioNavBar extends StatelessWidget {
  const _StudioNavBar({
    required this.c,
    required this.track,
    required this.accent,
  });

  final StudioController c;
  final Track track;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDrums = track.category.isBeatPrimary;

    return Material(
      color: StudioColors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accent.withValues(alpha: 0.55)),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.25),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isDrums
                            ? 'DRUMS'
                            : track.category.shortLabel.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: _modeSegment(c, track, accent),
          ),
          const Divider(height: 1, color: StudioColors.border),
        ],
      ),
    );
  }

  Widget _modeSegment(StudioController c, Track track, Color accent) {
    if (track.category == TrackCategory.drums) {
      final idx =
          track.effectiveMode == TrackInstrumentMode.drumPads ? 0 : 1;
      return ModeSegment(
        labels: const ['Pads', 'Step Seq'],
        selectedIndex: idx,
        accent: accent,
        onChanged: (i) {
          c.setTrackInstrumentMode(
            track,
            i == 0
                ? TrackInstrumentMode.drumPads
                : TrackInstrumentMode.stepSeq,
          );
          c.setTab(StudioTab.drums);
        },
      );
    }

    if (track.category == TrackCategory.bass) {
      final idx =
          track.effectiveMode == TrackInstrumentMode.pianoRoll ? 1 : 0;
      return ModeSegment(
        labels: const ['Fretboard', 'Piano Roll'],
        selectedIndex: idx,
        accent: accent,
        onChanged: (i) {
          c.setTrackInstrumentMode(
            track,
            i == 0
                ? TrackInstrumentMode.fretboard
                : TrackInstrumentMode.pianoRoll,
          );
          c.setTab(i == 0 ? StudioTab.keys : StudioTab.piano);
        },
      );
    }

    if (track.category == TrackCategory.keys) {
      final idx =
          track.effectiveMode == TrackInstrumentMode.pianoRoll ? 0 : 1;
      return ModeSegment(
        labels: const ['Piano Roll', 'Keyboard'],
        selectedIndex: idx,
        accent: accent,
        onChanged: (i) {
          c.setTrackInstrumentMode(
            track,
            i == 0
                ? TrackInstrumentMode.pianoRoll
                : TrackInstrumentMode.keyboard,
          );
          c.setTab(i == 0 ? StudioTab.piano : StudioTab.keys);
        },
      );
    }

    if (track.category == TrackCategory.guitar) {
      final idx =
          track.effectiveMode == TrackInstrumentMode.pianoRoll ? 0 : 1;
      return ModeSegment(
        labels: const ['Piano Roll', 'Strum'],
        selectedIndex: idx,
        accent: accent,
        onChanged: (i) {
          c.setTrackInstrumentMode(
            track,
            i == 0
                ? TrackInstrumentMode.pianoRoll
                : TrackInstrumentMode.guitarChords,
          );
          c.setTab(i == 0 ? StudioTab.piano : StudioTab.guitar);
        },
      );
    }

    return const SizedBox.shrink();
  }
}
