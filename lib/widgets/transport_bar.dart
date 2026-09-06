import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

class TransportBar extends StatelessWidget {
  const TransportBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project;
    if (p == null) return const SizedBox.shrink();

    final bar = (c.playheadStep ~/ p.stepsPerBar) + 1;
    final beat = ((c.playheadStep % p.stepsPerBar) ~/ 4) + 1;
    final step = (c.playheadStep % 4) + 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: StudioColors.surface,
        border: Border(top: BorderSide(color: StudioColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _Btn(
              icon: Icons.stop_rounded,
              onTap: c.stop,
            ),
            _Btn(
              icon: c.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: StudioColors.play,
              filled: true,
              onTap: c.togglePlay,
            ),
            const SizedBox(width: 10),
            Text(
              '${bar.toString().padLeft(2, '0')}.$beat.$step',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: () => _editBpm(context, c),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  '${p.bpm} BPM',
                  style: const TextStyle(
                    color: StudioColors.accent2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Loop',
              onPressed: () =>
                  c.updateProjectMeta(loopEnabled: !p.loopEnabled),
              icon: Icon(
                Icons.loop_rounded,
                color: p.loopEnabled
                    ? StudioColors.accent
                    : StudioColors.textDim,
              ),
            ),
            IconButton(
              tooltip: 'Export & Share',
              onPressed: () async {
                final err = await c.exportAndShare();
                if (context.mounted && err != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Export failed: $err')),
                  );
                }
              },
              icon: const Icon(Icons.ios_share_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editBpm(BuildContext context, StudioController c) async {
    final controller =
        TextEditingController(text: '${c.project?.bpm ?? 120}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tempo'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'BPM (40–240)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (result != null) c.updateProjectMeta(bpm: result);
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.onTap,
    this.color,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: filled
            ? (color ?? StudioColors.accent).withValues(alpha: 0.2)
            : StudioColors.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: color ?? StudioColors.text, size: 28),
          ),
        ),
      ),
    );
  }
}
