import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../utils/share_sheet.dart';
import '../widgets/arrange_view.dart';
import '../widgets/drum_pads.dart';
import '../widgets/empty_state.dart';
import '../widgets/fretboard.dart';
import '../widgets/guitar_chords.dart';
import '../widgets/piano_roll.dart';
import '../widgets/segmented_control.dart';
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

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        c.stop();
        unawaited(c.saveNow());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(p.name),
          actions: [
            IconButton(
              tooltip: 'MIDI in',
              onPressed: () => _openMidiSheet(context, c),
              icon: Icon(
                Icons.piano,
                color: c.midi.connected
                    ? StudioColors.accent2
                    : StudioColors.textDim,
              ),
            ),
            IconButton(
              tooltip: 'Export project (.layerstudio)',
              onPressed: () async {
                final err = await c.exportProjectBundle(
                  shareOrigin: shareSheetOrigin(context),
                );
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
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Saved')));
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
      ),
    );
  }

  bool _isBeatSurface(StudioTab tab) => switch (tab) {
    StudioTab.drums ||
    StudioTab.piano ||
    StudioTab.keys ||
    StudioTab.guitar => true,
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
        _EditorToolbar(c: c, track: track),
        Expanded(child: _editorBody(track)),
      ],
    );
  }

  Widget _editorBody(Track track) {
    return switch (track.effectiveMode) {
      TrackInstrumentMode.drumPads => DrumPads(track: track),
      TrackInstrumentMode.stepSeq => StepSequencer(track: track),
      TrackInstrumentMode.fretboard => InstrumentFretboard(track: track),
      TrackInstrumentMode.guitarChords => GuitarChordStrips(track: track),
      TrackInstrumentMode.keyboard => TouchKeyboard(track: track),
      TrackInstrumentMode.pianoRoll => PianoRoll(track: track),
      TrackInstrumentMode.micRecord => const Center(
        child: Text('Arm mic from Mixer / Arrange'),
      ),
    };
  }
}

/// Single compact row: track color badge + name + mode segmented control.
class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({required this.c, required this.track});
  final StudioController c;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final color = StudioColors.forTrack(track);
    final isDrums = track.category.isBeatPrimary;
    final mode = _modeSegment();

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isDrums
                      ? 'BEAT'
                      : 'LAYER · ${track.category.shortLabel.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: color,
                  ),
                ),
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (mode != null) ...[
            const SizedBox(width: 8),
            Expanded(flex: 3, child: mode),
          ],
        ],
      ),
    );
  }

  Widget? _modeSegment() {
    final color = StudioColors.forTrack(track);

    if (track.category == TrackCategory.drums) {
      final current = track.effectiveMode == TrackInstrumentMode.drumPads
          ? TrackInstrumentMode.drumPads
          : TrackInstrumentMode.stepSeq;
      return StudioSegmentedControl<TrackInstrumentMode>(
        accent: color,
        value: current,
        segments: const [
          StudioSegment(value: TrackInstrumentMode.drumPads, label: 'Pads'),
          StudioSegment(value: TrackInstrumentMode.stepSeq, label: 'Step Seq'),
        ],
        onChanged: (mode) {
          c.setTrackInstrumentMode(track, mode);
          c.setTab(StudioTab.drums);
        },
      );
    }

    if (track.category == TrackCategory.bass) {
      final mode = track.effectiveMode;
      final value = mode == TrackInstrumentMode.fretboard
          ? 'fret'
          : mode == TrackInstrumentMode.keyboard
          ? 'keys'
          : 'piano';
      return StudioSegmentedControl<String>(
        accent: color,
        value: value,
        segments: const [
          StudioSegment(value: 'fret', label: 'Fretboard'),
          StudioSegment(value: 'piano', label: 'Piano Roll'),
          StudioSegment(value: 'keys', label: 'Keys'),
        ],
        onChanged: (v) {
          if (v == 'fret') {
            c.setTrackInstrumentMode(track, TrackInstrumentMode.fretboard);
            c.setTab(StudioTab.piano);
          } else if (v == 'keys') {
            c.setTrackInstrumentMode(track, TrackInstrumentMode.keyboard);
            c.setTab(StudioTab.keys);
          } else {
            c.setTrackInstrumentMode(track, TrackInstrumentMode.pianoRoll);
            c.setTab(StudioTab.piano);
          }
        },
      );
    }

    if (track.category == TrackCategory.keys) {
      final onKeyboard =
          track.effectiveMode == TrackInstrumentMode.keyboard ||
          (track.instrumentMode == null && c.tab == StudioTab.keys);
      return StudioSegmentedControl<String>(
        accent: color,
        value: onKeyboard ? 'keyboard' : 'piano',
        segments: const [
          StudioSegment(value: 'piano', label: 'Piano Roll'),
          StudioSegment(value: 'keyboard', label: 'Keyboard'),
        ],
        onChanged: (v) {
          if (v == 'keyboard') {
            c.setTrackInstrumentMode(track, TrackInstrumentMode.keyboard);
            c.setTab(StudioTab.keys);
          } else {
            c.setTrackInstrumentMode(track, TrackInstrumentMode.pianoRoll);
            c.setTab(StudioTab.piano);
          }
        },
      );
    }

    if (track.category == TrackCategory.guitar) {
      final mode = track.effectiveMode;
      final value = mode == TrackInstrumentMode.fretboard
          ? 'fret'
          : mode == TrackInstrumentMode.pianoRoll
          ? 'piano'
          : 'chords';
      return StudioSegmentedControl<String>(
        accent: color,
        value: value,
        segments: const [
          StudioSegment(value: 'chords', label: 'Chords'),
          StudioSegment(value: 'fret', label: 'Fretboard'),
          StudioSegment(value: 'piano', label: 'Piano Roll'),
        ],
        onChanged: (v) {
          if (v == 'chords') {
            c.setTrackInstrumentMode(track, TrackInstrumentMode.guitarChords);
            c.setTab(StudioTab.guitar);
          } else if (v == 'fret') {
            c.setTrackInstrumentMode(track, TrackInstrumentMode.fretboard);
            c.setTab(StudioTab.guitar);
          } else {
            c.setTrackInstrumentMode(track, TrackInstrumentMode.pianoRoll);
            c.setTab(StudioTab.piano);
          }
        },
      );
    }

    return null;
  }
}

Future<void> _openMidiSheet(BuildContext context, StudioController c) async {
  final devices = await c.midi.devices();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: StudioColors.surface,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'MIDI input',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                c.midi.connected
                    ? 'Connected: ${c.midi.deviceName}'
                    : 'Notes play the selected track. Clock (24 ppqn) can set BPM.',
                style: const TextStyle(color: StudioColors.textDim, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (devices.isEmpty)
                const Text('No MIDI devices found.')
              else
                for (final d in devices)
                  ListTile(
                    title: Text(d.name),
                    subtitle: Text(d.connected ? 'Connected' : d.type.name),
                    onTap: () async {
                      await c.midi.connect(d);
                      c.notifyFxChanged();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
              if (c.midi.connected)
                TextButton(
                  onPressed: () async {
                    await c.midi.disconnect();
                    c.notifyFxChanged();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Disconnect'),
                ),
            ],
          ),
        ),
      );
    },
  );
}

