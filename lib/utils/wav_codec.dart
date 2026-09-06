import 'dart:math' as math;
import 'dart:typed_data';

/// Stereo PCM frames in floating [-1, 1] for offline mixdown / tests.
class StereoPcm {
  StereoPcm(this.left, this.right)
      : assert(left.length == right.length, 'L/R frame counts must match');

  final Float64List left;
  final Float64List right;

  int get frames => left.length;

  /// Dual-mono upmix.
  factory StereoPcm.mono(Float64List mono) {
    final r = Float64List.fromList(mono);
    return StereoPcm(mono, r);
  }

  factory StereoPcm.silence(int frames) =>
      StereoPcm(Float64List(frames), Float64List(frames));
}

/// Constant-power pan gains for track pan in [-1, 1].
({double l, double r}) panGains(double pan) {
  final p = pan.clamp(-1.0, 1.0);
  final angle = (p + 1.0) * (math.pi / 4.0);
  return (l: math.cos(angle), r: math.sin(angle));
}

/// Triangular PDF dither in [-1, 1] LSB units (sum of two uniform[-0.5, 0.5]).
double tpdfNoise(math.Random rng) =>
    rng.nextDouble() + rng.nextDouble() - 1.0;

/// Peak-normalize stereo buffers so |peak| <= [targetPeak] (default 0.95).
double peakNormalizeStereo(
  Float64List left,
  Float64List right, {
  double targetPeak = 0.95,
}) {
  var peak = 0.0;
  final n = left.length;
  for (var i = 0; i < n; i++) {
    final a = left[i].abs();
    final b = right[i].abs();
    if (a > peak) peak = a;
    if (b > peak) peak = b;
  }
  if (peak <= targetPeak || peak <= 0) return 1.0;
  final norm = targetPeak / peak;
  for (var i = 0; i < n; i++) {
    left[i] *= norm;
    right[i] *= norm;
  }
  return norm;
}

/// Quantize float stereo to interleaved PCM16 with optional TPDF dither.
Int16List quantizePcm16Stereo(
  Float64List left,
  Float64List right, {
  bool dither = true,
  math.Random? random,
}) {
  assert(left.length == right.length);
  final out = Int16List(left.length * 2);
  final rng = random ?? math.Random();
  for (var i = 0; i < left.length; i++) {
    final dL = dither ? tpdfNoise(rng) : 0.0;
    final dR = dither ? tpdfNoise(rng) : 0.0;
    out[i * 2] = (left[i] * 32767.0 + dL).round().clamp(-32768, 32767);
    out[i * 2 + 1] = (right[i] * 32767.0 + dR).round().clamp(-32768, 32767);
  }
  return out;
}

/// Quantize float stereo to interleaved PCM24 (3 bytes/sample, little-endian
/// packed into bytes by [encodeWavPcm24Stereo]).
Int32List quantizePcm24Stereo(Float64List left, Float64List right) {
  assert(left.length == right.length);
  final out = Int32List(left.length * 2);
  const scale = 8388607.0; // 2^23 - 1
  for (var i = 0; i < left.length; i++) {
    out[i * 2] = (left[i] * scale).round().clamp(-8388608, 8388607);
    out[i * 2 + 1] = (right[i] * scale).round().clamp(-8388608, 8388607);
  }
  return out;
}

/// Decode a PCM WAV (8/16/24-bit, mono or stereo) to stereo float frames.
/// Mono sources are dual-mono upmixed. Only the first two channels are kept.
StereoPcm? decodeWavStereo(Uint8List data) {
  if (data.length < 44) return null;
  final bd = ByteData.sublistView(data);
  if (String.fromCharCodes(data.sublist(0, 4)) != 'RIFF') return null;
  if (String.fromCharCodes(data.sublist(8, 12)) != 'WAVE') return null;

  var offset = 12;
  int? channels;
  int? bits;
  int? dataOffset;
  int? dataSize;
  while (offset + 8 <= data.length) {
    final id = String.fromCharCodes(data.sublist(offset, offset + 4));
    final size = bd.getUint32(offset + 4, Endian.little);
    if (id == 'fmt ') {
      channels = bd.getUint16(offset + 10, Endian.little);
      bits = bd.getUint16(offset + 22, Endian.little);
    } else if (id == 'data') {
      dataOffset = offset + 8;
      dataSize = size;
      break;
    }
    offset += 8 + size;
    if (size.isOdd) offset++;
  }
  if (dataOffset == null || channels == null || bits == null) return null;
  if (channels < 1 || !(bits == 8 || bits == 16 || bits == 24)) return null;

  final bytesPerSample = bits ~/ 8;
  final frameBytes = bytesPerSample * channels;
  if (frameBytes == 0) return null;
  final frameCount = dataSize! ~/ frameBytes;
  final left = Float64List(frameCount);
  final right = Float64List(frameCount);

  double readSample(int pos) {
    if (bits == 16) {
      return bd.getInt16(pos, Endian.little) / 32768.0;
    }
    if (bits == 8) {
      return (data[pos] - 128) / 128.0;
    }
    // 24-bit little-endian packed
    final b0 = data[pos];
    final b1 = data[pos + 1];
    final b2 = data[pos + 2];
    var v = b0 | (b1 << 8) | (b2 << 16);
    if (v >= 0x800000) v -= 0x1000000; // sign-extend 24-bit
    return v / 8388608.0;
  }

  for (var i = 0; i < frameCount; i++) {
    final pos = dataOffset + i * frameBytes;
    final l = readSample(pos);
    final r = channels == 1 ? l : readSample(pos + bytesPerSample);
    left[i] = l;
    right[i] = r;
  }
  return StereoPcm(left, right);
}

/// Encode interleaved PCM16 stereo WAV (channels=2).
Uint8List encodeWavPcm16Stereo(Int16List interleaved, int sampleRate) {
  assert(interleaved.length.isEven);
  final dataSize = interleaved.length * 2;
  final buffer = ByteData(44 + dataSize);
  void writeStr(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      buffer.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  const channels = 2;
  const bits = 16;
  final byteRate = sampleRate * channels * (bits ~/ 8);
  final blockAlign = channels * (bits ~/ 8);

  writeStr(0, 'RIFF');
  buffer.setUint32(4, 36 + dataSize, Endian.little);
  writeStr(8, 'WAVE');
  writeStr(12, 'fmt ');
  buffer.setUint32(16, 16, Endian.little);
  buffer.setUint16(20, 1, Endian.little); // PCM
  buffer.setUint16(22, channels, Endian.little);
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, byteRate, Endian.little);
  buffer.setUint16(32, blockAlign, Endian.little);
  buffer.setUint16(34, bits, Endian.little);
  writeStr(36, 'data');
  buffer.setUint32(40, dataSize, Endian.little);
  var o = 44;
  for (final s in interleaved) {
    buffer.setInt16(o, s, Endian.little);
    o += 2;
  }
  return buffer.buffer.asUint8List();
}

/// Encode interleaved PCM24 stereo WAV (channels=2). Clean optional path.
Uint8List encodeWavPcm24Stereo(Int32List interleaved, int sampleRate) {
  assert(interleaved.length.isEven);
  final dataSize = interleaved.length * 3;
  final buffer = ByteData(44 + dataSize);
  void writeStr(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      buffer.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  const channels = 2;
  const bits = 24;
  final byteRate = sampleRate * channels * (bits ~/ 8);
  final blockAlign = channels * (bits ~/ 8);

  writeStr(0, 'RIFF');
  buffer.setUint32(4, 36 + dataSize, Endian.little);
  writeStr(8, 'WAVE');
  writeStr(12, 'fmt ');
  buffer.setUint32(16, 16, Endian.little);
  buffer.setUint16(20, 1, Endian.little);
  buffer.setUint16(22, channels, Endian.little);
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, byteRate, Endian.little);
  buffer.setUint16(32, blockAlign, Endian.little);
  buffer.setUint16(34, bits, Endian.little);
  writeStr(36, 'data');
  buffer.setUint32(40, dataSize, Endian.little);
  var o = 44;
  for (final s in interleaved) {
    final v = s & 0xFFFFFF;
    buffer.setUint8(o, v & 0xFF);
    buffer.setUint8(o + 1, (v >> 8) & 0xFF);
    buffer.setUint8(o + 2, (v >> 16) & 0xFF);
    o += 3;
  }
  return buffer.buffer.asUint8List();
}

/// Parse common WAV fmt fields for tests / validation.
({int channels, int sampleRate, int bitsPerSample, int dataSize})? readWavFormat(
  Uint8List data,
) {
  if (data.length < 44) return null;
  final bd = ByteData.sublistView(data);
  if (String.fromCharCodes(data.sublist(0, 4)) != 'RIFF') return null;
  if (String.fromCharCodes(data.sublist(8, 12)) != 'WAVE') return null;
  var offset = 12;
  int? channels;
  int? sampleRate;
  int? bits;
  int? dataSize;
  while (offset + 8 <= data.length) {
    final id = String.fromCharCodes(data.sublist(offset, offset + 4));
    final size = bd.getUint32(offset + 4, Endian.little);
    if (id == 'fmt ') {
      channels = bd.getUint16(offset + 10, Endian.little);
      sampleRate = bd.getUint32(offset + 12, Endian.little);
      bits = bd.getUint16(offset + 22, Endian.little);
    } else if (id == 'data') {
      dataSize = size;
      break;
    }
    offset += 8 + size;
    if (size.isOdd) offset++;
  }
  if (channels == null || sampleRate == null || bits == null || dataSize == null) {
    return null;
  }
  return (
    channels: channels,
    sampleRate: sampleRate,
    bitsPerSample: bits,
    dataSize: dataSize,
  );
}
