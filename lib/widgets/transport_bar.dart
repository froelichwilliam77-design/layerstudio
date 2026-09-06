import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/error_log.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

class TransportBar extends StatefulWidget {
  const TransportBar({super.key});

  @override
  State<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends State<TransportBar> {
  bool _settingsOpen = false;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project;
    if (p == null) return const SizedBox.shrink();

    final bar = (c.playheadStep ~/ p.stepsPerBar) + 1;
    final beat = ((c.playheadStep % p.stepsPerBar) ~/ 4) + 1;
    final step = (c.playheadStep % 4) + 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: StudioColors.surface,
        border: Border(top: BorderSide(color: StudioColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _Btn(icon: Icons.stop_rounded, onTap: c.stop),
                _Btn(
                  icon: c.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: c.isRecordingMic
                      ? StudioColors.danger
                      : StudioColors.play,
                  filled: true,
                  onTap: c.togglePlay,
                ),
                const SizedBox(width: 6),
                Text(
                  c.isCountingIn
                      ? 'COUNT ${c.countInStepsRemaining}'
                      : '${bar.toString().padLeft(2, '0')}.$beat.$step',
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _editBpm(context, c),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      '${p.bpm}',
                      style: const TextStyle(
                        color: StudioColors.accent2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Undo',
                  onPressed: c.commands.canUndo ? c.undo : null,
                  icon: const Icon(Icons.undo, size: 20),
                ),
                IconButton(
                  tooltip: 'Redo',
                  onPressed: c.commands.canRedo ? c.redo : null,
                  icon: const Icon(Icons.redo, size: 20),
                ),
                IconButton(
                  tooltip: 'Metronome',
                  onPressed: () => c.updateProjectMeta(
                    metronomeEnabled: !p.metronomeEnabled,
                  ),
                  icon: Icon(
                    Icons.timer_outlined,
                    size: 20,
                    color: p.metronomeEnabled
                        ? StudioColors.accent
                        : StudioColors.textDim,
                  ),
                ),
                IconButton(
                  tooltip: 'Loop',
                  onPressed: () =>
                      c.updateProjectMeta(loopEnabled: !p.loopEnabled),
                  icon: Icon(
                    Icons.loop_rounded,
                    size: 20,
                    color: p.loopEnabled
                        ? StudioColors.accent
                        : StudioColors.textDim,
                  ),
                ),
                IconButton(
                  tooltip: _settingsOpen ? 'Hide settings' : 'Swing & arrange',
                  onPressed: () =>
                      setState(() => _settingsOpen = !_settingsOpen),
                  icon: Icon(
                    _settingsOpen
                        ? Icons.expand_more_rounded
                        : Icons.tune_rounded,
                    size: 20,
                    color: _settingsOpen
                        ? StudioColors.accent
                        : StudioColors.textDim,
                  ),
                ),
                IconButton(
                  tooltip: 'Export WAV',
                  onPressed: () async {
                    final err = await c.exportAndShare();
                    if (context.mounted && err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Export failed: $err')),
                      );
                    }
                  },
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'Copy last error',
                  onPressed: () async {
                    await ErrorLog.instance.copyLastToClipboard();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ErrorLog.instance.lastError == null
                                ? 'No errors recorded'
                                : 'Last error copied',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                ),
              ],
            ),
            if (_settingsOpen)
              Row(
                children: [
                  const Text('Swing',
                      style: TextStyle(
                          fontSize: 11, color: StudioColors.textDim)),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 100,
                      divisions: 20,
                      value: p.swingPercent.toDouble(),
                      label: '${p.swingPercent}%',
                      onChanged: (v) =>
                          c.updateProjectMeta(swingPercent: v.round()),
                    ),
                  ),
                  PopupMenuButton<int>(
                    tooltip: 'Count-in',
                    initialValue: p.countInBars,
                    onSelected: (v) => c.updateProjectMeta(countInBars: v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 0, child: Text('Count-in off')),
                      PopupMenuItem(value: 1, child: Text('1 bar count-in')),
                      PopupMenuItem(value: 2, child: Text('2 bar count-in')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        p.countInBars == 0
                            ? 'Count'
                            : 'Count×${p.countInBars}',
                        style: TextStyle(
                          fontSize: 11,
                          color: p.countInBars > 0
                              ? StudioColors.accent
                              : StudioColors.textDim,
                        ),
                      ),
                    ),
                  ),
                  FilterChip(
                    label: Text(p.songMode ? 'Song' : 'Pattern',
                        style: const TextStyle(fontSize: 11)),
                    selected: p.songMode,
                    showCheckmark: false,
                    onSelected: (v) => c.updateProjectMeta(songMode: v),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
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
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: filled
            ? (color ?? StudioColors.accent).withValues(alpha: 0.2)
            : StudioColors.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: color ?? StudioColors.text, size: 26),
          ),
        ),
      ),
    );
  }
}
