import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

/// Microphone capture. Returns a WAV file's bytes on stop.
abstract interface class VoiceRecorder {
  /// False when the user refused microphone access.
  Future<bool> start();
  Future<Uint8List?> stop();
  Future<void> cancel();
}

/// Speaker output for spoken replies.
abstract interface class AudioOutput {
  Future<void> playMp3(Uint8List bytes);
  Future<void> stop();
}

const _sampleRate = 16000;

/// Streams 16-bit PCM (supported by `record` on web and Android alike) and
/// wraps it in a WAV header, so there are no platform-specific file paths.
class MicVoiceRecorder implements VoiceRecorder {
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  final _chunks = BytesBuilder(copy: false);

  @override
  Future<bool> start() async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) return false;
    _chunks.clear();
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
    );
    _sub = stream.listen(_chunks.add);
    return true;
  }

  @override
  Future<Uint8List?> stop() async {
    final recorder = _recorder;
    if (recorder == null) return null;
    await recorder.stop();
    await _sub?.cancel();
    _sub = null;
    final pcm = _chunks.takeBytes();
    if (pcm.isEmpty) return null;
    return wavFromPcm16(pcm, sampleRate: _sampleRate);
  }

  @override
  Future<void> cancel() async {
    await _recorder?.cancel();
    await _sub?.cancel();
    _sub = null;
    _chunks.clear();
  }
}

/// A mono 16-bit PCM WAV file around [pcm].
Uint8List wavFromPcm16(Uint8List pcm, {required int sampleRate}) {
  final header = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // fmt chunk size
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .takeBytes();
}

class SpeakerAudioOutput implements AudioOutput {
  AudioPlayer? _player;

  @override
  Future<void> playMp3(Uint8List bytes) async {
    final player = _player ??= AudioPlayer();
    await player.stop();
    await player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
  }

  @override
  Future<void> stop() async => _player?.stop();

  Future<void> dispose() async => _player?.dispose();
}

final voiceRecorderProvider = Provider.autoDispose<VoiceRecorder>((ref) {
  final r = MicVoiceRecorder();
  ref.onDispose(r.cancel);
  return r;
});

final audioOutputProvider = Provider.autoDispose<AudioOutput>((ref) {
  final o = SpeakerAudioOutput();
  ref.onDispose(o.dispose);
  return o;
});
