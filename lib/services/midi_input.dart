import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_midi_command/flutter_midi_command_messages.dart';

/// MIDI note-on/off + clock (24 ppqn) BPM estimate.
class MidiInputService {
  MidiInputService();

  final MidiCommand _midi = MidiCommand();
  StreamSubscription<MidiDataReceivedEvent>? _sub;
  DateTime? _lastClock;
  final List<int> _clockGapsMs = [];

  void Function(int midi, int velocity)? onNoteOn;
  void Function(int midi)? onNoteOff;
  void Function(int bpm)? onClockBpm;

  bool connected = false;
  String? deviceName;
  int? lastBpm;

  Future<List<MidiDevice>> devices() async {
    try {
      return (await _midi.devices) ?? [];
    } catch (e) {
      debugPrint('MIDI devices failed: $e');
      return [];
    }
  }

  Future<void> connect(MidiDevice device) async {
    await disconnect();
    try {
      await _midi.connectToDevice(device);
      deviceName = device.name;
      connected = true;
      _sub = _midi.onMidiDataReceived?.listen(_onEvent);
    } catch (e) {
      debugPrint('MIDI connect failed: $e');
      connected = false;
    }
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    if (connected) {
      try {
        final list = await devices();
        for (final d in list) {
          if (d.name == deviceName) {
            _midi.disconnectDevice(d);
          }
        }
      } catch (_) {}
    }
    connected = false;
    deviceName = null;
  }

  void _onEvent(MidiDataReceivedEvent event) {
    final msg = event.message;
    if (msg is ClockMessage && msg.type == ClockType.beat) {
      _onClock();
      return;
    }
    if (msg is NoteOnMessage) {
      if (msg.velocity > 0) {
        onNoteOn?.call(msg.note, msg.velocity);
      } else {
        onNoteOff?.call(msg.note);
      }
      return;
    }
    if (msg is NoteOffMessage) {
      onNoteOff?.call(msg.note);
      return;
    }
    _onRaw(msg.data);
  }

  void _onRaw(List<int> data) {
    if (data.isEmpty) return;
    var i = 0;
    while (i < data.length) {
      final b = data[i];
      if (b == 0xF8) {
        _onClock();
        i++;
        continue;
      }
      final type = b & 0xF0;
      if (type == 0x90 && i + 2 < data.length) {
        final note = data[i + 1];
        final vel = data[i + 2];
        if (vel > 0) {
          onNoteOn?.call(note, vel);
        } else {
          onNoteOff?.call(note);
        }
        i += 3;
        continue;
      }
      if (type == 0x80 && i + 2 < data.length) {
        onNoteOff?.call(data[i + 1]);
        i += 3;
        continue;
      }
      i++;
    }
  }

  void _onClock() {
    final now = DateTime.now();
    final last = _lastClock;
    _lastClock = now;
    if (last == null) return;
    final gap = now.difference(last).inMilliseconds;
    if (gap < 5 || gap > 200) return;
    _clockGapsMs.add(gap);
    if (_clockGapsMs.length > 24) _clockGapsMs.removeAt(0);
    if (_clockGapsMs.length < 12) return;
    final avg = _clockGapsMs.reduce((a, b) => a + b) / _clockGapsMs.length;
    final bpm = (60000.0 / (avg * 24)).round().clamp(40, 240);
    if (bpm != lastBpm) {
      lastBpm = bpm;
      onClockBpm?.call(bpm);
    }
  }

  Future<void> dispose() => disconnect();
}
