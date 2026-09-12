import 'dart:typed_data';

/// Decoded PCM, as mono samples in the range -1 to 1.
class PcmAudio {
  const PcmAudio({
    required this.samples,
    required this.sampleRate,
  });

  final Float64List samples;
  final int sampleRate;

  Duration get duration => Duration(
        microseconds: sampleRate == 0
            ? 0
            : (samples.length * 1000000 / sampleRate).round(),
      );
}

/// Reads uncompressed PCM out of a WAV file.
///
/// Deliberately minimal: it handles what the platform decoder writes (8, 16, 24
/// and 32-bit integer PCM, plus 32-bit float) and nothing else. Anything
/// exotic throws rather than returning quietly wrong samples, because silently
/// misread audio would show up as a flicker pattern that looks plausible and
/// is meaningless.
class WavReader {
  WavReader._();

  /// Parses [bytes], mixing any multi-channel audio down to mono.
  static PcmAudio parse(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const FormatException('Not a WAV file: too short');
    }

    final data = ByteData.sublistView(bytes);

    if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE file');
    }

    var offset = 12;
    var channels = 1;
    var sampleRate = 44100;
    var bitsPerSample = 16;
    var isFloat = false;
    Uint8List? pcm;

    // Chunks can appear in any order, and the platform encoder is free to add
    // its own, so this walks them rather than assuming a fixed layout.
    while (offset + 8 <= bytes.length) {
      final id = _tag(bytes, offset);
      final size = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;

      if (id == 'fmt ' && body + 16 <= bytes.length) {
        final format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bitsPerSample = data.getUint16(body + 14, Endian.little);

        // 1 is integer PCM, 3 is IEEE float, 0xFFFE defers to the extension.
        isFloat = format == 3;
        if (format != 1 && format != 3 && format != 0xFFFE) {
          throw FormatException('Unsupported WAV format code $format');
        }
      } else if (id == 'data') {
        final end = (body + size).clamp(0, bytes.length);
        pcm = Uint8List.sublistView(bytes, body, end);
      }

      // Chunks are word aligned.
      offset = body + size + (size.isOdd ? 1 : 0);
    }

    if (pcm == null) {
      throw const FormatException('WAV file has no data chunk');
    }
    if (channels < 1) {
      throw const FormatException('WAV file declares no channels');
    }

    final samples = _toMono(
      pcm,
      channels: channels,
      bitsPerSample: bitsPerSample,
      isFloat: isFloat,
    );

    return PcmAudio(samples: samples, sampleRate: sampleRate);
  }

  static Float64List _toMono(
    Uint8List pcm, {
    required int channels,
    required int bitsPerSample,
    required bool isFloat,
  }) {
    final bytesPerSample = bytesFor(bitsPerSample);
    final frameBytes = bytesPerSample * channels;
    if (frameBytes == 0) return Float64List(0);

    final frames = pcm.lengthInBytes ~/ frameBytes;
    final output = Float64List(frames);
    final view = ByteData.sublistView(pcm);

    for (var frame = 0; frame < frames; frame++) {
      var sum = 0.0;
      for (var channel = 0; channel < channels; channel++) {
        final at = frame * frameBytes + channel * bytesPerSample;
        sum += _sampleAt(view, at, bitsPerSample, isFloat);
      }
      output[frame] = sum / channels;
    }

    return output;
  }

  static int bytesFor(int bitsPerSample) => switch (bitsPerSample) {
        8 => 1,
        16 => 2,
        24 => 3,
        32 => 4,
        _ => throw FormatException('Unsupported bit depth $bitsPerSample'),
      };

  static double _sampleAt(
    ByteData view,
    int at,
    int bitsPerSample,
    bool isFloat,
  ) {
    switch (bitsPerSample) {
      case 8:
        // 8-bit WAV is unsigned, centred on 128.
        return (view.getUint8(at) - 128) / 128.0;
      case 16:
        return view.getInt16(at, Endian.little) / 32768.0;
      case 24:
        final b0 = view.getUint8(at);
        final b1 = view.getUint8(at + 1);
        final b2 = view.getUint8(at + 2);
        var value = b0 | (b1 << 8) | (b2 << 16);
        // Sign-extend the 24-bit value.
        if ((value & 0x800000) != 0) value |= ~0xFFFFFF;
        return value / 8388608.0;
      case 32:
        if (isFloat) return view.getFloat32(at, Endian.little);
        return view.getInt32(at, Endian.little) / 2147483648.0;
      default:
        throw FormatException('Unsupported bit depth $bitsPerSample');
    }
  }

  static String _tag(Uint8List bytes, int at) {
    if (at + 4 > bytes.length) return '';
    return String.fromCharCodes(bytes.sublist(at, at + 4));
  }
}
