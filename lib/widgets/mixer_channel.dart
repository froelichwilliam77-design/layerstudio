import 'package:flutter/material.dart';

import '../models/fx_settings.dart';
import '../models/track.dart';
import '../theme/studio_theme.dart';

class MixerChannel extends StatelessWidget {
  const MixerChannel({
    super.key,
    required this.track,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onToggleMute,
    this.onToggleSolo,
    this.onToggleCue,
    this.onToggleOverdub,
  });

  final Track track;
  final VoidCallback onChanged;
  final VoidCallback? onChangeStart;
  final VoidCallback? onChangeEnd;
  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleSolo;
  final VoidCallback? onToggleCue;
  final VoidCallback? onToggleOverdub;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StudioColors.border),
      ),
      child: Column(
        children: [
          Text(
            track.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(track.colorValue),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Tiny(
                label: 'M',
                active: track.muted,
                color: StudioColors.warning,
                onTap: onToggleMute ??
                    () {
                      track.muted = !track.muted;
                      onChanged();
                    },
              ),
              const SizedBox(width: 4),
              _Tiny(
                label: 'S',
                active: track.solo,
                color: StudioColors.accent,
                onTap: onToggleSolo ??
                    () {
                      track.solo = !track.solo;
                      onChanged();
                    },
              ),
              const SizedBox(width: 4),
              _Tiny(
                label: 'C',
                active: track.cue,
                color: StudioColors.accent2,
                onTap: onToggleCue ??
                    () {
                      track.cue = !track.cue;
                      onChanged();
                    },
              ),
            ],
          ),
          Expanded(
            child: RotatedBox(
              quarterTurns: -1,
              child: Slider(
                value: track.volume,
                onChangeStart: (_) => onChangeStart?.call(),
                onChanged: (v) {
                  track.volume = v;
                  onChanged();
                },
                onChangeEnd: (_) => onChangeEnd?.call(),
              ),
            ),
          ),
          Text('${(track.volume * 100).round()}%',
              style: const TextStyle(fontSize: 11)),
          const Text('Pan', style: TextStyle(fontSize: 10, color: StudioColors.textDim)),
          Slider(
            value: track.pan,
            min: -1,
            max: 1,
            onChangeStart: (_) => onChangeStart?.call(),
            onChanged: (v) {
              track.pan = v;
              onChanged();
            },
            onChangeEnd: (_) => onChangeEnd?.call(),
          ),
          const Divider(height: 12),
          const Text('FX', style: TextStyle(fontSize: 10, color: StudioColors.textDim)),
          _fxSlider('Rev', track.fx.reverb, (v) {
            track.fx.reverb = v;
            onChanged();
          }),
          _fxSlider('Dly', track.fx.delay, (v) {
            track.fx.delay = v;
            onChanged();
          }),
          _fxSlider('Lo', (track.fx.eqLow + 1) / 2, (v) {
            track.fx.eqLow = v * 2 - 1;
            onChanged();
          }),
          _fxSlider('Hi', (track.fx.eqHigh + 1) / 2, (v) {
            track.fx.eqHigh = v * 2 - 1;
            onChanged();
          }),
          _fxSlider('Cmp', track.fx.comp, (v) {
            track.fx.comp = v;
            onChanged();
          }),
          DropdownButton<AmpPreset>(
            isExpanded: true,
            value: track.fx.ampPreset,
            underline: const SizedBox.shrink(),
            items: AmpPreset.values
                .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e.label, style: const TextStyle(fontSize: 11)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              track.fx.ampPreset = v;
              onChanged();
            },
          ),
          if (track.category == TrackCategory.mic) ...[
            const Divider(height: 8),
            _Tiny(
              label: 'OD',
              active: track.overdub,
              color: StudioColors.record,
              onTap: onToggleOverdub ??
                  () {
                    track.overdub = !track.overdub;
                    onChanged();
                  },
            ),
            const Text('Latency',
                style: TextStyle(fontSize: 9, color: StudioColors.textDim)),
            Slider(
              value: track.latencyMs.toDouble().clamp(0, 250),
              min: 0,
              max: 250,
              divisions: 25,
              onChangeStart: (_) => onChangeStart?.call(),
              onChanged: (v) {
                track.latencyMs = v.round();
                onChanged();
              },
              onChangeEnd: (_) => onChangeEnd?.call(),
            ),
            Text('${track.latencyMs} ms', style: const TextStyle(fontSize: 9)),
          ],
        ],
      ),
    );
  }

  Widget _fxSlider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(label, style: const TextStyle(fontSize: 9)),
        ),
        Expanded(
          child: Slider(
            value: value,
            onChangeStart: (_) => onChangeStart?.call(),
            onChanged: onChanged,
            onChangeEnd: (_) => onChangeEnd?.call(),
          ),
        ),
      ],
    );
  }
}

class _Tiny extends StatelessWidget {
  const _Tiny({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.35) : StudioColors.surface2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? color : StudioColors.border),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: active ? color : StudioColors.textDim,
            )),
      ),
    );
  }
}
