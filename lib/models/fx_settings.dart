/// Simple per-track FX / amp chain (UI + export DSP; live uses SoLoud filters).
class FxSettings {
  FxSettings({
    this.ampPreset = AmpPreset.clean,
    this.reverb = 0.15,
    this.delay = 0.0,
    this.eqLow = 0.0,
    this.eqMid = 0.0,
    this.eqHigh = 0.0,
    this.comp = 0.2,
    this.gain = 0.45,
    this.tone = 0.55,
    this.cabSim = true,
  });

  AmpPreset ampPreset;
  double reverb; // 0–1
  double delay; // 0–1
  double eqLow; // -1..1
  double eqMid;
  double eqHigh;
  double comp; // 0–1

  /// Mini Amp Sim: Gain / Drive (0–1). Audibly drives SoLoud wave-shaper.
  double gain;

  /// Mini Amp Sim: Tone / Brightness (0–1). Maps to biquad + export EQ.
  double tone;

  /// Mini Amp Sim: Cab Sim toggle (cabinet-ish freeverb damp + lowpass).
  bool cabSim;

  FxSettings copyWith({
    AmpPreset? ampPreset,
    double? reverb,
    double? delay,
    double? eqLow,
    double? eqMid,
    double? eqHigh,
    double? comp,
    double? gain,
    double? tone,
    bool? cabSim,
  }) {
    return FxSettings(
      ampPreset: ampPreset ?? this.ampPreset,
      reverb: reverb ?? this.reverb,
      delay: delay ?? this.delay,
      eqLow: eqLow ?? this.eqLow,
      eqMid: eqMid ?? this.eqMid,
      eqHigh: eqHigh ?? this.eqHigh,
      comp: comp ?? this.comp,
      gain: gain ?? this.gain,
      tone: tone ?? this.tone,
      cabSim: cabSim ?? this.cabSim,
    );
  }

  Map<String, dynamic> toJson() => {
        'ampPreset': ampPreset.name,
        'reverb': reverb,
        'delay': delay,
        'eqLow': eqLow,
        'eqMid': eqMid,
        'eqHigh': eqHigh,
        'comp': comp,
        'gain': gain,
        'tone': tone,
        'cabSim': cabSim,
      };

  factory FxSettings.fromJson(Map<String, dynamic> json) {
    final rawCab = json['cabSim'];
    final cab = rawCab is bool
        ? rawCab
        : rawCab is num
            ? rawCab > 0.5
            : true;
    return FxSettings(
      ampPreset: AmpPreset.values.firstWhere(
        (e) => e.name == json['ampPreset'],
        orElse: () => AmpPreset.clean,
      ),
      reverb: (json['reverb'] as num?)?.toDouble() ?? 0.15,
      delay: (json['delay'] as num?)?.toDouble() ?? 0.0,
      eqLow: (json['eqLow'] as num?)?.toDouble() ?? 0.0,
      eqMid: (json['eqMid'] as num?)?.toDouble() ?? 0.0,
      eqHigh: (json['eqHigh'] as num?)?.toDouble() ?? 0.0,
      comp: (json['comp'] as num?)?.toDouble() ?? 0.2,
      gain: (json['gain'] as num?)?.toDouble() ?? 0.45,
      tone: (json['tone'] as num?)?.toDouble() ?? 0.55,
      cabSim: cab,
    );
  }
}

enum AmpPreset { clean, crunch, highGain, bassDrive, none }

extension AmpPresetLabel on AmpPreset {
  String get label => switch (this) {
        AmpPreset.clean => 'Clean',
        AmpPreset.crunch => 'Crunch',
        AmpPreset.highGain => 'High Gain',
        AmpPreset.bassDrive => 'Bass Drive',
        AmpPreset.none => 'Bypass',
      };
}
