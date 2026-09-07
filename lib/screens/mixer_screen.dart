import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/mixer_channel.dart';

class MixerScreen extends StatelessWidget {
  const MixerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project!;
    if (p.tracks.isEmpty) {
      return EmptyState(
        icon: Icons.tune,
        title: 'Nothing to mix yet',
        subtitle: 'Add drums or an instrument first.',
        actionLabel: 'Add drums',
        onAction: () => c.setTab(StudioTab.library),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              FilterChip(
                label: Text(p.cueMode ? 'CUE mix ON' : 'CUE mix'),
                selected: p.cueMode,
                onSelected: (v) => c.updateProjectMeta(cueMode: v),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'C = pre-fade listen. Only cued tracks play when CUE mix is on.',
                  style: TextStyle(fontSize: 11, color: StudioColors.textDim),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final t in p.tracks)
                MixerChannel(
                  track: t,
                  onChanged: () => c.updateTrack(t),
                  onChangeStart: c.beginGestureUndo,
                  onChangeEnd: () => c.endGestureUndo('Mixer'),
                  onToggleMute: () => c.toggleMute(t),
                  onToggleSolo: () => c.toggleSolo(t),
                  onToggleCue: () => c.toggleCue(t),
                  onToggleOverdub: () => c.toggleOverdub(t),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
