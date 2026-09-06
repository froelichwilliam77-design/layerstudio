import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fx_settings.dart';
import '../models/track.dart';
import '../services/studio_controller.dart';
import '../theme/studio_theme.dart';

/// Collapsible Mini Amp Sim for bass/guitar tracks.
///
/// Live path: [AudioEngine._applyVoiceFx] via SoLoud wave-shaper (Gain),
/// biquad low-pass (Tone), freeverb damp/wet (Cab). Offline: [SimpleDsp].
class MiniAmpPanel extends StatefulWidget {
  const MiniAmpPanel({super.key, required this.track});
  final Track track;

  @override
  State<MiniAmpPanel> createState() => _MiniAmpPanelState();
}

class _MiniAmpPanelState extends State<MiniAmpPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<StudioController>();
    final accent = Color(widget.track.colorValue);
    final fx = widget.track.fx;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(
        color: StudioColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.speaker, size: 16, color: accent),
                  const SizedBox(width: 8),
                  const Text(
                    'Mini Amp Sim',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    fx.ampPreset.label,
                    style: TextStyle(fontSize: 11, color: accent),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    color: StudioColors.textDim,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1, color: StudioColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Column(
                children: [
                  _knob(
                    'Gain / Drive',
                    fx.gain,
                    accent,
                    (v) {
                      fx.gain = v;
                      c.updateTrackFx(widget.track);
                    },
                  ),
                  _knob(
                    'Tone / Bright',
                    fx.tone,
                    accent,
                    (v) {
                      fx.tone = v;
                      c.updateTrackFx(widget.track);
                    },
                  ),
                  Row(
                    children: [
                      const SizedBox(
                        width: 96,
                        child: Text(
                          'Cab Sim',
                          style: TextStyle(
                            fontSize: 11,
                            color: StudioColors.textDim,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: fx.cabSim,
                        activeThumbColor: accent,
                        activeTrackColor: accent.withValues(alpha: 0.45),
                        onChanged: (v) {
                          fx.cabSim = v;
                          c.updateTrackFx(widget.track);
                        },
                      ),
                      Text(
                        fx.cabSim ? 'On' : 'Off',
                        style: TextStyle(
                          fontSize: 11,
                          color: fx.cabSim ? accent : StudioColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _knob(
    String label,
    double value,
    Color accent,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: StudioColors.textDim),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              thumbColor: accent,
              inactiveTrackColor: StudioColors.border,
            ),
            child: Slider(
              min: 0,
              max: 1,
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${(value * 100).round()}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: StudioColors.textDim),
          ),
        ),
      ],
    );
  }
}
