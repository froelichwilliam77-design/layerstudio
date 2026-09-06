import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/sound_library.dart';
import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';
import 'param_lock_sheet.dart';

class StepSequencer extends StatelessWidget {
  const StepSequencer({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final p = c.project!;
    final preset = SoundLibrary.byId(track.presetId);
    final kit = preset?.drumKit;
    if (kit == null) return const SizedBox.shrink();
    final names = kit.keys.toList();
    const steps = 16;
    final pages = (p.loopEndStep / steps).ceil().clamp(1, 8);
    final trackColor = StudioColors.forTrack(track);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Row(
            children: [
              Text(
                '16-step',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: trackColor,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < p.patterns.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        _PatternPill(
                          label: p.patterns[i].name,
                          selected: p.activePatternIndex == i,
                          color: trackColor,
                          onTap: () => c.selectPattern(i),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'clear_pattern':
                      c.clearPattern(p.activePatternIndex);
                    case 'clear_track':
                      c.clearTrackNotes(track.id);
                    case 'clear_all':
                      c.clearTrackAllPatterns(track.id);
                    case 'copy_to_b':
                      c.copyPattern(
                          fromIndex: p.activePatternIndex, toIndex: 1);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'clear_pattern', child: Text('Clear pattern')),
                  PopupMenuItem(
                      value: 'clear_track',
                      child: Text('Clear track (pattern)')),
                  PopupMenuItem(
                      value: 'clear_all',
                      child: Text('Clear track (all patterns)')),
                  PopupMenuItem(
                      value: 'copy_to_b', child: Text('Copy pattern → B')),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
          child: Row(
            children: [
              Text(
                'Vel ${c.drawVelocity}',
                style: const TextStyle(
                    fontSize: 11, color: StudioColors.textDim),
              ),
              Expanded(
                child: Slider(
                  min: 20,
                  max: 127,
                  value: c.drawVelocity.toDouble(),
                  activeColor: trackColor,
                  onChanged: (v) => c.setDrawVelocity(v.round()),
                ),
              ),
              Text(
                'Prob ${c.drawProbability}%',
                style: const TextStyle(
                    fontSize: 11, color: StudioColors.textDim),
              ),
              SizedBox(
                width: 72,
                child: Slider(
                  min: 0,
                  max: 100,
                  divisions: 20,
                  value: c.drawProbability.toDouble(),
                  onChanged: (v) => c.setDrawProbability(v.round()),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Drag across steps to paint · tap toggles · long-press lit step for locks',
              style: TextStyle(fontSize: 10, color: StudioColors.textDim),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: pages,
            itemBuilder: (context, page) {
              final offset = page * steps;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Bar ${page + 1}',
                        style: const TextStyle(color: StudioColors.textDim),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          for (var pad = 0; pad < names.length; pad++)
                            _PadRow(
                              label: names[pad],
                              track: track,
                              padIndex: pad,
                              offset: offset,
                              steps: steps,
                              playhead: c.playheadStep,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PadRow extends StatefulWidget {
  const _PadRow({
    required this.label,
    required this.track,
    required this.padIndex,
    required this.offset,
    required this.steps,
    required this.playhead,
  });

  final String label;
  final Track track;
  final int padIndex;
  final int offset;
  final int steps;
  final int playhead;

  @override
  State<_PadRow> createState() => _PadRowState();
}

class _PadRowState extends State<_PadRow> {
  static const stepW = 28.0;
  static const stepGap = 4.0;
  static const labelW = 78.0;

  final Set<int> _trail = {};
  bool _paintOn = true;
  bool _moved = false;
  bool _pendingToggle = false;
  int? _startStep;

  int? _stepAt(Offset local) {
    final x = local.dx - labelW;
    if (x < 0) return null;
    final stride = stepW + stepGap;
    final i = (x / stride).floor();
    if (i < 0 || i >= widget.steps) return null;
    // Only hit if within the step cell (not the gap).
    final within = x - i * stride;
    if (within > stepW) return null;
    return widget.offset + i;
  }

  Future<void> _openParamLock(
    BuildContext context,
    StudioController c,
    int step,
  ) async {
    if (!c.isStepOn(widget.track, widget.padIndex, step)) return;
    final vel = c.stepVelocity(widget.track, widget.padIndex, step);
    final prob = c.stepProbability(widget.track, widget.padIndex, step);
    final trackColor = StudioColors.forTrack(widget.track);
    final result = await showParamLockSheet(
      context,
      accent: trackColor,
      velocity: vel,
      probability: prob,
      showLength: false,
      title: 'Step lock · ${widget.label}',
    );
    if (result == null) return;
    if (result.delete) {
      c.beginNoteStroke(widget.track.id);
      c.paintStepCell(
        trackId: widget.track.id,
        padIndex: widget.padIndex,
        step: step,
        on: false,
      );
      c.endNoteStroke(label: 'Delete step');
      return;
    }
    c.setStepVelocity(
      trackId: widget.track.id,
      padIndex: widget.padIndex,
      step: step,
      velocity: result.velocity,
    );
    c.setStepProbability(
      trackId: widget.track.id,
      padIndex: widget.padIndex,
      step: step,
      probability: result.probability,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final trackColor = StudioColors.forTrack(widget.track);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Listener(
        onPointerDown: (e) {
          final step = _stepAt(e.localPosition);
          if (step == null) return;
          final on = c.isStepOn(widget.track, widget.padIndex, step);
          _trail
            ..clear()
            ..add(step);
          _moved = false;
          _startStep = step;
          _pendingToggle = false;

          if (on) {
            // Tap → toggle off; drag → erase stroke; long-press → param lock.
            _paintOn = false;
            _pendingToggle = true;
            c.beginNoteStroke(widget.track.id);
          } else {
            _paintOn = true;
            c.beginNoteStroke(widget.track.id);
            c.paintStepCell(
              trackId: widget.track.id,
              padIndex: widget.padIndex,
              step: step,
              on: true,
            );
          }
          setState(() {});
        },
        onPointerMove: (e) {
          if (_startStep == null) return;
          final step = _stepAt(e.localPosition);
          if (step == null) return;
          if (step != _startStep && !_moved) {
            _moved = true;
            if (_pendingToggle) {
              c.paintStepCell(
                trackId: widget.track.id,
                padIndex: widget.padIndex,
                step: _startStep!,
                on: false,
              );
              _pendingToggle = false;
            }
          }
          if (_trail.contains(step)) return;
          _trail.add(step);
          if (_pendingToggle) return;
          c.paintStepCell(
            trackId: widget.track.id,
            padIndex: widget.padIndex,
            step: step,
            on: _paintOn,
          );
          setState(() {});
        },
        onPointerUp: (_) {
          final moved = _moved;
          final start = _startStep;
          final pending = _pendingToggle;
          final paintOn = _paintOn;
          if (!moved && pending && start != null) {
            // Tap on lit step → toggle off (foundation behavior).
            c.paintStepCell(
              trackId: widget.track.id,
              padIndex: widget.padIndex,
              step: start,
              on: false,
            );
          }
          c.endNoteStroke(label: paintOn ? 'Paint steps' : 'Erase steps');
          _trail.clear();
          _startStep = null;
          _pendingToggle = false;
          if (mounted) setState(() {});
        },
        onPointerCancel: (_) {
          c.endNoteStroke(label: 'Paint steps');
          _trail.clear();
          _startStep = null;
          _pendingToggle = false;
          if (mounted) setState(() {});
        },
        child: Row(
          children: [
            SizedBox(
              width: labelW,
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: trackColor.withValues(alpha: 0.85),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (var s = 0; s < widget.steps; s++)
              Builder(builder: (context) {
                final step = widget.offset + s;
                final on = c.isStepOn(widget.track, widget.padIndex, step);
                final isPlay = widget.playhead == step;
                final beat = s % 4 == 0;
                final vel =
                    on ? c.stepVelocity(widget.track, widget.padIndex, step) : 0;
                final prob = on
                    ? c.stepProbability(widget.track, widget.padIndex, step)
                    : 100;
                return Padding(
                  padding: EdgeInsets.only(
                      right: s == widget.steps - 1 ? 0 : stepGap),
                  child: GestureDetector(
                    onLongPress: on
                        ? () async {
                            // Cancel tap-toggle stroke; open floating param lock.
                            _pendingToggle = false;
                            _startStep = null;
                            _trail.clear();
                            c.endNoteStroke(label: 'Paint steps');
                            if (mounted) setState(() {});
                            await _openParamLock(context, c, step);
                          }
                        : null,
                    child: _VelocityStep(
                      on: on,
                      velocity: vel,
                      probability: prob,
                      isPlay: isPlay,
                      beat: beat,
                      color: trackColor,
                      trail: _trail.contains(step),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// Solid luminous fill; height + intensity map to step velocity.
class _VelocityStep extends StatelessWidget {
  const _VelocityStep({
    required this.on,
    required this.velocity,
    required this.probability,
    required this.isPlay,
    required this.beat,
    required this.color,
    this.trail = false,
  });

  final bool on;
  final int velocity;
  final int probability;
  final bool isPlay;
  final bool beat;
  final Color color;
  final bool trail;

  @override
  Widget build(BuildContext context) {
    const w = 28.0;
    const h = 36.0;
    final velT = (velocity / 127.0).clamp(0.0, 1.0);
    final fillH = on ? (10.0 + velT * (h - 10.0)) : 0.0;
    final alpha = on ? (0.45 + velT * 0.55).clamp(0.45, 1.0) : 0.0;
    final dimForProb = on ? (probability / 100.0).clamp(0.35, 1.0) : 1.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: beat ? StudioColors.surface2 : StudioColors.bg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isPlay
              ? StudioColors.play
              : trail
                  ? color.withValues(alpha: 0.85)
                  : (on ? color.withValues(alpha: 0.55) : StudioColors.border),
          width: isPlay || trail ? 2 : 1,
        ),
        boxShadow: on
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35 * velT),
                  blurRadius: 6 + 6 * velT,
                  spreadRadius: 0.2,
                ),
              ]
            : trail
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 6,
                    ),
                  ]
                : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          if (trail && !on)
            Container(
              width: w,
              height: h,
              color: color.withValues(alpha: 0.22),
            ),
          if (on)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: w,
                height: fillH,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      color.withValues(alpha: alpha * dimForProb),
                      color.withValues(alpha: (alpha * 0.75) * dimForProb),
                    ],
                  ),
                ),
              ),
            ),
          if (on && probability < 100)
            Positioned(
              top: 2,
              child: Text(
                '$probability',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: StudioColors.text.withValues(alpha: 0.85),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PatternPill extends StatelessWidget {
  const _PatternPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : StudioColors.surface2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : StudioColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? StudioColors.bg : StudioColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}
