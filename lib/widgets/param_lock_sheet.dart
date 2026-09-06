import 'package:flutter/material.dart';

import '../theme/studio_theme.dart';

/// Result of a parameter-lock edit (velocity / length / probability).
class ParamLockResult {
  const ParamLockResult({
    required this.velocity,
    required this.probability,
    this.lengthSteps,
    this.delete = false,
  });

  final int velocity;
  final int probability;
  final int? lengthSteps;
  final bool delete;
}

/// Floating semi-transparent overlay to edit per-note / per-step locks
/// without leaving the grid (visual-guide §3).
Future<ParamLockResult?> showParamLockSheet(
  BuildContext context, {
  required Color accent,
  required int velocity,
  required int probability,
  int? lengthSteps,
  bool showLength = false,
  String title = 'Parameter lock',
}) {
  return showGeneralDialog<ParamLockResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, anim, secondary) {
      return SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: _ParamLockCard(
            accent: accent,
            velocity: velocity,
            probability: probability,
            lengthSteps: lengthSteps,
            showLength: showLength,
            title: title,
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ParamLockCard extends StatefulWidget {
  const _ParamLockCard({
    required this.accent,
    required this.velocity,
    required this.probability,
    required this.lengthSteps,
    required this.showLength,
    required this.title,
  });

  final Color accent;
  final int velocity;
  final int probability;
  final int? lengthSteps;
  final bool showLength;
  final String title;

  @override
  State<_ParamLockCard> createState() => _ParamLockCardState();
}

class _ParamLockCardState extends State<_ParamLockCard> {
  late double _vel;
  late double _prob;
  late double _len;

  @override
  void initState() {
    super.initState();
    _vel = widget.velocity.toDouble().clamp(1, 127);
    _prob = widget.probability.toDouble().clamp(0, 100);
    _len = (widget.lengthSteps ?? 1).toDouble().clamp(1, 16);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: StudioColors.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.accent.withValues(alpha: 0.45)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 18, color: widget.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: StudioColors.text,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                  color: StudioColors.textDim,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Velocity ${_vel.round()}',
              style: const TextStyle(fontSize: 12, color: StudioColors.textDim),
            ),
            Slider(
              min: 1,
              max: 127,
              value: _vel,
              activeColor: widget.accent,
              onChanged: (v) => setState(() => _vel = v),
            ),
            if (widget.showLength) ...[
              Text(
                'Length ${_len.round()} step${_len.round() == 1 ? '' : 's'}',
                style:
                    const TextStyle(fontSize: 12, color: StudioColors.textDim),
              ),
              Slider(
                min: 1,
                max: 16,
                divisions: 15,
                value: _len,
                activeColor: widget.accent,
                onChanged: (v) => setState(() => _len = v),
              ),
            ],
            Text(
              'Probability ${_prob.round()}%',
              style: const TextStyle(fontSize: 12, color: StudioColors.textDim),
            ),
            Slider(
              min: 0,
              max: 100,
              divisions: 20,
              value: _prob,
              activeColor: widget.accent,
              onChanged: (v) => setState(() => _prob = v),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(
                    context,
                    ParamLockResult(
                      velocity: _vel.round(),
                      probability: _prob.round(),
                      lengthSteps: widget.showLength ? _len.round() : null,
                      delete: true,
                    ),
                  ),
                  child: const Text('Delete',
                      style: TextStyle(color: StudioColors.danger)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: widget.accent),
                  onPressed: () => Navigator.pop(
                    context,
                    ParamLockResult(
                      velocity: _vel.round(),
                      probability: _prob.round(),
                      lengthSteps: widget.showLength ? _len.round() : null,
                    ),
                  ),
                  child: const Text('Set'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
