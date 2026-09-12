import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:storm_sync/audio/fft.dart';
import 'package:storm_sync/audio/thunder_envelope.dart';
import 'package:storm_sync/audio/wav_reader.dart';

/// Builds PCM containing a tone at [frequency], optionally with a burst of
/// high-frequency content partway through.
PcmAudio _tone({
  required double frequency,
  int sampleRate = 22050,
  double seconds = 1.0,
  double amplitude = 0.8,
}) {
  final count = (sampleRate * seconds).round();
  final samples = Float64List(count);
  for (var i = 0; i < count; i++) {
    samples[i] = amplitude * sin(2 * pi * frequency * i / sampleRate);
  }
  return PcmAudio(samples: samples, sampleRate: sampleRate);
}

ThunderEnvelope _envelope(List<SpectralFrame> frames, {int frameMs = 20}) {
  return ThunderEnvelope(
    frames: frames,
    frameMs: frameMs,
    duration: Duration(milliseconds: frames.length * frameMs),
  );
}

SpectralFrame _f(double low, double mid, double high) =>
    SpectralFrame(low: low, mid: mid, high: high);

void main() {
  group('FFT', () {
    test('finds the bin of a pure tone', () {
      const sampleRate = 22050;
      const frequency = 1000.0;
      final fft = Fft(1024);

      final samples = Float64List(1024);
      for (var i = 0; i < 1024; i++) {
        samples[i] = sin(2 * pi * frequency * i / sampleRate);
      }

      final magnitudes = fft.magnitudes(samples);

      var peakBin = 0;
      for (var i = 1; i < magnitudes.length; i++) {
        if (magnitudes[i] > magnitudes[peakBin]) peakBin = i;
      }

      expect(
        fft.frequencyOf(peakBin, sampleRate),
        closeTo(frequency, 40),
        reason: 'the strongest bin should be the tone that was fed in',
      );
    });

    test('bin lookup round-trips', () {
      final fft = Fft(1024);
      const sampleRate = 22050;

      for (final frequency in [100.0, 500.0, 2000.0, 6000.0]) {
        final bin = fft.binFor(frequency, sampleRate);
        expect(fft.frequencyOf(bin, sampleRate), closeTo(frequency, 25));
      }
    });

    test('silence produces no magnitude', () {
      final fft = Fft(256);
      final magnitudes = fft.magnitudes(Float64List(256));
      expect(magnitudes.every((m) => m < 1e-9), isTrue);
    });

    test('rejects a non power-of-two size', () {
      expect(() => Fft(1000), throwsA(isA<AssertionError>()));
    });
  });

  group('band analysis', () {
    test('a low tone lands in the low band', () {
      final envelope = ThunderEnvelopeStore.analyse(_tone(frequency: 90));
      expect(envelope.frames, isNotEmpty);

      final frame = envelope.frames[envelope.frames.length ~/ 2];
      expect(frame.low, greaterThan(0.5));
      expect(frame.high, lessThan(0.2));
      expect(frame.brightness, lessThan(0.4),
          reason: 'a low rumble should not read as a sharp crack');
    });

    test('a high tone lands in the high band', () {
      final envelope = ThunderEnvelopeStore.analyse(_tone(frequency: 5000));
      final frame = envelope.frames[envelope.frames.length ~/ 2];

      expect(frame.high, greaterThan(0.5));
      expect(frame.low, lessThan(0.2));
      expect(frame.brightness, greaterThan(0.6),
          reason: 'a crack should read as sharp');
    });

    test('a mid tone lands in the mid band', () {
      final envelope = ThunderEnvelopeStore.analyse(_tone(frequency: 900));
      final frame = envelope.frames[envelope.frames.length ~/ 2];

      expect(frame.mid, greaterThan(frame.low));
      expect(frame.mid, greaterThan(frame.high));
    });

    test('empty audio yields an empty envelope rather than throwing', () {
      final envelope = ThunderEnvelopeStore.analyse(
        PcmAudio(samples: Float64List(0), sampleRate: 22050),
      );
      expect(envelope.isEmpty, isTrue);
      expect(envelope.peaks(minGapMs: 40), isEmpty);
    });
  });

  group('peak picking follows onsets in the sharp bands', () {
    test('flashes on a sharp onset, not on a steady rumble', () {
      // A long, loud, steady low rumble with one sharp crack in the middle.
      final frames = [
        for (var i = 0; i < 100; i++) _f(0.9, 0.05, 0.02),
      ];
      frames[50] = _f(0.9, 0.8, 0.95);

      final peaks = _envelope(frames).peaks(minGapMs: 60);

      expect(peaks, hasLength(1),
          reason: 'the steady rumble offers nothing to flash at');
      expect(peaks.single.at.inMilliseconds, 1000);

      // A crack sitting on top of a loud rumble still carries a lot of low
      // energy, so its sharpness is diluted. What matters is that it is far
      // sharper than the rumble it interrupts.
      final rumbleBrightness = _f(0.9, 0.05, 0.02).brightness;
      expect(peaks.single.brightness, greaterThan(rumbleBrightness * 3));
      expect(peaks.single.brightness, greaterThan(0.45));
    });

    test('a loud low thump reads as less sharp than a crack', () {
      final thump = [
        for (var i = 0; i < 40; i++) _f(0.05, 0.02, 0.01),
      ];
      thump[20] = _f(0.95, 0.2, 0.05);

      final crack = [
        for (var i = 0; i < 40; i++) _f(0.05, 0.02, 0.01),
      ];
      crack[20] = _f(0.3, 0.8, 0.95);

      final thumpPeak = _envelope(thump).peaks(minGapMs: 60).single;
      final crackPeak = _envelope(crack).peaks(minGapMs: 60).single;

      expect(crackPeak.brightness, greaterThan(thumpPeak.brightness));
    });

    test('a slower link yields fewer, more separated flashes', () {
      final frames = <SpectralFrame>[];
      for (var i = 0; i < 200; i++) {
        final sharp = i % 3 == 0 ? 0.8 : 0.05;
        frames.add(_f(0.3, sharp * 0.6, sharp));
      }

      final envelope = _envelope(frames);
      final fast = envelope.peaks(minGapMs: 40);
      final slow = envelope.peaks(minGapMs: 200);

      expect(slow.length, lessThan(fast.length));
      for (var i = 1; i < slow.length; i++) {
        final gap = slow[i].at.inMilliseconds - slow[i - 1].at.inMilliseconds;
        expect(gap, greaterThanOrEqualTo(200));
      }
    });

    test('the number of flashes is capped and stays in time order', () {
      final frames = <SpectralFrame>[];
      for (var i = 0; i < 600; i++) {
        frames.add(i % 2 == 0 ? _f(0.2, 0.5, 0.7) : _f(0.2, 0.02, 0.02));
      }

      final peaks = _envelope(frames).peaks(minGapMs: 40, limit: 10);

      expect(peaks, hasLength(10));
      for (var i = 1; i < peaks.length; i++) {
        expect(peaks[i].at, greaterThan(peaks[i - 1].at));
      }
    });

    test('rumbleTrack exposes the low band for the between-flash floor', () {
      final envelope = _envelope([_f(0.8, 0.1, 0.1), _f(0.2, 0.1, 0.1)]);
      expect(envelope.rumbleTrack(), [0.8, 0.2]);
    });

    test('loudestAt finds the biggest moment overall', () {
      final frames = [_f(0.1, 0.1, 0.1), _f(0.9, 0.9, 0.9), _f(0.2, 0.2, 0.2)];
      expect(_envelope(frames).loudestAt.inMilliseconds, 20);
    });

    test('frameAt clamps outside the recording', () {
      final envelope = _envelope([_f(0.5, 0.5, 0.5)]);

      expect(envelope.frameAt(Duration.zero).low, 0.5);
      expect(envelope.frameAt(const Duration(hours: 1)).total, 0);
      expect(envelope.frameAt(const Duration(milliseconds: -50)).total, 0);
    });
  });

  group('WAV reading', () {
    Uint8List buildWav({
      required List<int> samples,
      int sampleRate = 22050,
      int channels = 1,
      int bitsPerSample = 16,
    }) {
      final bytesPer = bitsPerSample ~/ 8;
      final dataBytes = samples.length * bytesPer;
      final bytes = BytesBuilder();

      void ascii(String s) => bytes.add(s.codeUnits);
      void u32(int v) =>
          bytes.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
      void u16(int v) =>
          bytes.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

      ascii('RIFF');
      u32(36 + dataBytes);
      ascii('WAVE');
      ascii('fmt ');
      u32(16);
      u16(1);
      u16(channels);
      u32(sampleRate);
      u32(sampleRate * channels * bytesPer);
      u16(channels * bytesPer);
      u16(bitsPerSample);
      ascii('data');
      u32(dataBytes);

      final payload = Uint8List(dataBytes);
      final view = payload.buffer.asByteData();
      for (var i = 0; i < samples.length; i++) {
        view.setInt16(i * 2, samples[i], Endian.little);
      }
      bytes.add(payload);

      return bytes.toBytes();
    }

    test('reads 16-bit mono PCM', () {
      final wav = buildWav(samples: [0, 16384, -16384, 32767]);
      final pcm = WavReader.parse(wav);

      expect(pcm.sampleRate, 22050);
      expect(pcm.samples, hasLength(4));
      expect(pcm.samples[0], closeTo(0, 0.001));
      expect(pcm.samples[1], closeTo(0.5, 0.001));
      expect(pcm.samples[2], closeTo(-0.5, 0.001));
      expect(pcm.samples[3], closeTo(1.0, 0.001));
    });

    test('mixes stereo down to mono', () {
      // Two channels, opposite signs, should cancel to silence.
      final wav = buildWav(samples: [16384, -16384], channels: 2);
      final pcm = WavReader.parse(wav);

      expect(pcm.samples, hasLength(1));
      expect(pcm.samples[0], closeTo(0, 0.001));
    });

    test('duration follows sample count and rate', () {
      final wav = buildWav(
        samples: List<int>.filled(22050, 0),
        sampleRate: 22050,
      );
      expect(WavReader.parse(wav).duration.inMilliseconds, 1000);
    });

    test('rejects a file that is not RIFF/WAVE', () {
      expect(
        () => WavReader.parse(Uint8List.fromList(List.filled(64, 0x41))),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a truncated file', () {
      expect(
        () => WavReader.parse(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('locating the strike inside a long recording', () {
    /// Two minutes of near-silence with the thunder 80 seconds in, which is
    /// what the bundled samples actually look like.
    ThunderEnvelope buried() {
      final frames = <SpectralFrame>[];
      for (var i = 0; i < 6000; i++) {
        frames.add(_f(0.05, 0.01, 0.01));
      }
      // A cluster of cracks at 80-84 seconds (frames 4000-4200).
      for (var i = 4000; i < 4200; i += 20) {
        frames[i] = _f(0.6, 0.8, 0.95);
      }
      return _envelope(frames);
    }

    test('finds the thunder rather than the silent opening', () {
      final start = buried().strikeStart(windowMs: 9000);

      expect(
        start.inMilliseconds,
        greaterThan(70000),
        reason: 'the strike is 80 seconds in, not at the start of the file',
      );
      expect(start.inMilliseconds, lessThan(80000));
    });

    test('backs up slightly so the attack is not clipped', () {
      final start = buried().strikeStart(windowMs: 9000, leadInMs: 400);
      // The first crack is at frame 4000, which is 80000ms.
      expect(start.inMilliseconds, 79600);
    });

    test('a recording with no thunder starts at the beginning', () {
      final silent = _envelope([
        for (var i = 0; i < 200; i++) _f(0.02, 0.01, 0.01),
      ]);
      expect(silent.strikeStart(), Duration.zero);
    });

    test('the lead-in never runs off the front of the file', () {
      final early = _envelope([
        for (var i = 0; i < 200; i++) _f(0.05, 0.01, 0.01),
      ]);
      final frames = List<SpectralFrame>.from(early.frames);
      frames[2] = _f(0.5, 0.8, 0.9);

      final start = _envelope(frames).strikeStart(leadInMs: 5000);
      expect(start, Duration.zero);
    });

    test('picks the busiest stretch, not merely the first hit', () {
      final frames = <SpectralFrame>[];
      for (var i = 0; i < 4000; i++) {
        frames.add(_f(0.05, 0.01, 0.01));
      }
      // One lone early tap.
      frames[200] = _f(0.3, 0.4, 0.45);
      // A dense cluster much later.
      for (var i = 2000; i < 2300; i += 15) {
        frames[i] = _f(0.6, 0.85, 0.95);
      }

      final start = _envelope(frames).strikeStart(windowMs: 9000);
      expect(start.inMilliseconds, greaterThan(30000));
    });
  });
}
