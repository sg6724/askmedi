import 'dart:typed_data';

import 'package:askmedi/core/platform/audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wavFromPcm16 writes a valid 44-byte mono 16-bit header', () {
    final pcm = Uint8List.fromList(List.filled(320, 7));
    final wav = wavFromPcm16(pcm, sampleRate: 16000);
    final h = ByteData.sublistView(wav);

    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(h.getUint32(4, Endian.little), 36 + 320);
    expect(h.getUint16(22, Endian.little), 1); // mono
    expect(h.getUint32(24, Endian.little), 16000);
    expect(h.getUint16(34, Endian.little), 16);
    expect(h.getUint32(40, Endian.little), 320);
    expect(wav.length, 44 + 320);
  });
}
