import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:layerstudio/utils/wav_codec.dart';

Uint8List _minimalMono16(List<int> samples, {int sr = 44100}) {
  final pcm = Int16List.fromList(samples);
  final dataSize = pcm.length * 2;
  final buf = ByteData(44 + dataSize);
  void ws(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      buf.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  ws(0, 'RIFF');
  buf.setUint32(4, 36 + dataSize, Endian.little);
  ws(8, 'WAVE');
  ws(12, 'fmt ');
  buf.setUint32(16, 16, Endian.little);
  buf.setUint16(20, 1, Endian.little);
  buf.setUint16(22, 1, Endian.little);
  buf.setUint32(24, sr, Endian.little);
  buf.setUint32(28, sr * 2, Endian.little);
  buf.setUint16(32, 2, Endian.little);
  buf.setUint16(34, 16, Endian.little);
  ws(36, 'data');
  buf.setUint32(40, dataSize, Endian.little);
  var o = 44;
  for (final s in pcm) {
    buf.setInt16(o, s, Endian.little);
    o += 2;
  }
  return buf.buffer.asUint8List();
}

void main() {
  group('wav_codec stereo + dither', () {
    test('decode mono WAV upmixes to dual mono', () {
      final bytes = _minimalMono16([0, 16384, -16384, 32767]);
      final pcm = decodeWavStereo(bytes);
      expect(pcm, isNotNull);
      expect(pcm!.frames, 4);
      expect(pcm.left[1], closeTo(0.5, 0.01));
      expect(pcm.right[1], closeTo(pcm.left[1], 1e-12));
      expect(pcm.left[2], closeTo(pcm.right[2], 1e-12));
    });

    test('encode stereo 16-bit header has channels=2', () {
      final left = Float64List.fromList([0.0, 0.25, -0.5, 0.9]);
      final right = Float64List.fromList([0.1, -0.25, 0.5, -0.9]);
      final pcm16 = quantizePcm16Stereo(left, right, dither: false);
      final wav = encodeWavPcm16Stereo(pcm16, 44100);
      final fmt = readWavFormat(wav);
      expect(fmt, isNotNull);
      expect(fmt!.channels, 2);
      expect(fmt.sampleRate, 44100);
      expect(fmt.bitsPerSample, 16);
      expect(fmt.dataSize, left.length * 2 * 2);
      // RIFF / WAVE magic
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    });

    test('roundtrip stereo preserves distinct L/R', () {
      final left = Float64List.fromList([0.5, -0.25, 0.0, 0.75]);
      final right = Float64List.fromList([-0.5, 0.25, 0.1, -0.75]);
      final pcm16 = quantizePcm16Stereo(left, right, dither: false);
      final wav = encodeWavPcm16Stereo(pcm16, 44100);
      final decoded = decodeWavStereo(wav)!;
      for (var i = 0; i < left.length; i++) {
        expect(decoded.left[i], closeTo(left[i], 0.002));
        expect(decoded.right[i], closeTo(right[i], 0.002));
        // Channels must stay distinct (not collapsed to mono).
        if (left[i] != right[i]) {
          expect(decoded.left[i], isNot(closeTo(decoded.right[i], 0.001)));
        }
      }
    });

    test('TPDF dither changes quiet quantization vs undithered', () {
      // Very quiet DC that truncates to 0 without dither sometimes,
      // but with dither should produce a non-zero variance over many samples.
      final n = 4096;
      final left = Float64List(n);
      final right = Float64List(n);
      for (var i = 0; i < n; i++) {
        left[i] = 0.5 / 32768.0; // half LSB
        right[i] = -0.5 / 32768.0;
      }
      final undithered = quantizePcm16Stereo(left, right, dither: false);
      final dithered = quantizePcm16Stereo(
        left,
        right,
        dither: true,
        random: math.Random(42),
      );
      var undithNonZero = 0;
      var dithNonZero = 0;
      for (var i = 0; i < undithered.length; i++) {
        if (undithered[i] != 0) undithNonZero++;
        if (dithered[i] != 0) dithNonZero++;
      }
      expect(dithNonZero, greaterThan(undithNonZero));
      // Dithered values stay near ±1 LSB (not wild).
      for (final s in dithered) {
        expect(s.abs(), lessThanOrEqualTo(2));
      }
    });

    test('panGains is constant-power at center and edges', () {
      final c = panGains(0);
      expect(c.l, closeTo(math.sqrt(0.5), 1e-9));
      expect(c.r, closeTo(math.sqrt(0.5), 1e-9));
      final hardL = panGains(-1);
      expect(hardL.l, closeTo(1.0, 1e-9));
      expect(hardL.r, closeTo(0.0, 1e-9));
      final hardR = panGains(1);
      expect(hardR.l, closeTo(0.0, 1e-9));
      expect(hardR.r, closeTo(1.0, 1e-9));
    });

    test('peakNormalizeStereo scales both channels', () {
      final l = Float64List.fromList([0.0, 2.0]);
      final r = Float64List.fromList([-1.5, 0.0]);
      final g = peakNormalizeStereo(l, r, targetPeak: 0.95);
      expect(g, closeTo(0.95 / 2.0, 1e-12));
      expect(l[1].abs(), closeTo(0.95, 1e-12));
      expect(r[0].abs(), closeTo(1.5 * g, 1e-12));
    });

    test('24-bit encode header channels=2 bits=24', () {
      final left = Float64List.fromList([0.1, -0.2]);
      final right = Float64List.fromList([-0.1, 0.2]);
      final pcm24 = quantizePcm24Stereo(left, right);
      final wav = encodeWavPcm24Stereo(pcm24, 44100);
      final fmt = readWavFormat(wav);
      expect(fmt!.channels, 2);
      expect(fmt.bitsPerSample, 24);
      expect(fmt.dataSize, left.length * 2 * 3);
      final decoded = decodeWavStereo(wav)!;
      expect(decoded.left[0], closeTo(0.1, 1e-5));
      expect(decoded.right[1], closeTo(0.2, 1e-5));
    });

    test('tpdfNoise stays in [-1, 1]', () {
      final rng = math.Random(7);
      for (var i = 0; i < 2000; i++) {
        final n = tpdfNoise(rng);
        expect(n, inInclusiveRange(-1.0, 1.0));
      }
    });
  });
}
