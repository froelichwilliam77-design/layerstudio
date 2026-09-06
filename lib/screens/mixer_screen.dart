import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/studio_controller.dart';
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

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        for (final t in p.tracks)
          MixerChannel(
            track: t,
            onChanged: () => c.updateTrack(t),
          ),
      ],
    );
  }
}
