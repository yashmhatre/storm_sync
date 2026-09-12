import 'dart:io';
import 'dart:math';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'fft.dart';
import 'thunder_player.dart';
import 'wav_reader.dart';

/// Energy in three frequency bands at one moment in a recording.
///
/// Thunder is two different sounds layered together, and they want two
/// different things from the light. The crack is broadband and sudden and
/// belongs to the sharp flashes; the rumble is almost entirely low frequency
/// and belongs to a slow swell. Splitting them is what lets the strip track the
/// sound rather than just its loudness.
@immutable
class SpectralFrame {
  const SpectralFrame({
    required this.low,
    required this.mid,
    required this.high,
  });

  /// Roughly 20-250 Hz. The body of a rumble.
  final double low;

  /// Roughly 250-2000 Hz.
  final double mid;

  /// Roughly 2-8 kHz. The crack, and the sharp edge of a nearby strike.
  final double high;

  /// Overall loudness of the frame.
  double get total => (low + mid + high) / 3;

  /// How much of this frame is the sharp end of the spectrum.
  ///
  /// Near 1 is a crack, near 0 is a rumble. This is what decides whether a
  /// moment becomes a hard flash or a slow swell.
  double get brightness {
    final sum = low + mid + high;
    if (sum <= 0) return 0;
    return ((mid * 0.5 + high) / sum).clamp(0.0, 1.0);
  }

  static const SpectralFrame silent =
      SpectralFrame(low: 0, mid: 0, high: 0);
}

/// A recording's loudness over time, split into frequency bands.
@immutable
class ThunderEnvelope {
  const ThunderEnvelope({
    required this.frames,
    required this.frameMs,
    required this.duration,
  });

  final List<SpectralFrame> frames;

  /// How much time one entry in [frames] covers.
  final int frameMs;

  final Duration duration;

  bool get isEmpty => frames.isEmpty;

  SpectralFrame frameAt(Duration position) {
    if (frames.isEmpty) return SpectralFrame.silent;
    final index = position.inMilliseconds ~/ frameMs;
    if (index < 0 || index >= frames.length) return SpectralFrame.silent;
    return frames[index];
  }

  /// Picks the moments worth flashing on.
  ///
  /// Peaks are found in the **sharp** part of the spectrum, not in overall
  /// loudness. A long low rumble is loud for seconds on end and offers nothing
  /// to flash at; the cracks and the sharp edges within it do, and those live
  /// in the mid and high bands.
  ///
  /// Real thunder has far more detail than an acknowledged BLE link can carry,
  /// so this is a deliberate reduction: local maxima above [threshold], spaced
  /// at least [minGapMs] apart. That gap comes from the measured write cost, so
  /// a fast link gets a busier strike and a slow one degrades to the biggest
  /// hits rather than falling behind the audio.
  List<EnvelopePeak> peaks({
    required int minGapMs,
    double threshold = 0.14,
    int limit = 48,
  }) {
    if (frames.length < 3) return const [];

    // The detection signal is the sharp bands only.
    final sharp = List<double>.generate(frames.length, (i) {
      final frame = frames[i];
      return (frame.mid * 0.45 + frame.high).clamp(0.0, 2.0);
    });

    // Onset strength: how much sharper this moment is than the one before it.
    // Flashing on rises rather than on absolute level is what puts light on
    // the attack of a crack instead of somewhere in its decay.
    final onset = List<double>.generate(sharp.length, (i) {
      if (i == 0) return 0.0;
      return max(0.0, sharp[i] - sharp[i - 1]);
    });

    final peak = onset.fold<double>(0, max);
    if (peak <= 0) return const [];

    final minGapFrames = max(1, minGapMs ~/ frameMs);
    final found = <EnvelopePeak>[];
    var lastIndex = -minGapFrames;

    for (var i = 1; i < onset.length - 1; i++) {
      final value = onset[i] / peak;
      if (value < threshold) continue;
      if (onset[i] < onset[i - 1] || onset[i] < onset[i + 1]) continue;

      final frame = frames[i];

      if (i - lastIndex < minGapFrames) {
        // Too close to the previous flash to be written separately. Keep the
        // stronger onset so a big hit is never lost to a small one that
        // happened to come first.
        if (found.isNotEmpty && value > found.last.strength) {
          found[found.length - 1] = EnvelopePeak(
            at: Duration(milliseconds: i * frameMs),
            strength: value,
            amplitude: frame.total,
            brightness: frame.brightness,
          );
          lastIndex = i;
        }
        continue;
      }

      found.add(EnvelopePeak(
        at: Duration(milliseconds: i * frameMs),
        strength: value,
        amplitude: frame.total,
        brightness: frame.brightness,
      ));
      lastIndex = i;
    }

    if (found.length <= limit) return found;

    final byStrength = List<EnvelopePeak>.from(found)
      ..sort((a, b) => b.strength.compareTo(a.strength));
    return byStrength.take(limit).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
  }

  /// Where in the recording the strike actually is.
  ///
  /// Field recordings of storms are mostly quiet: a sample can run for minutes
  /// with the only real thunder somewhere in the middle. Following the opening
  /// of such a file flashes the strip at silence, so the strike is located
  /// first and both the light and the audio start from here.
  ///
  /// Picks the [windowMs] stretch carrying the most onset energy, then backs up
  /// by [leadInMs] so the attack is not clipped off the front.
  Duration strikeStart({
    int windowMs = 9000,
    int leadInMs = 400,
    int minGapMs = 60,
  }) {
    final found = peaks(minGapMs: minGapMs);
    if (found.isEmpty) return Duration.zero;

    final window = Duration(milliseconds: windowMs);

    var bestStart = found.first.at;
    var bestScore = 0.0;

    // Each peak is tried as the opening of the window, which is enough when
    // the window only ever starts on a real onset.
    for (final candidate in found) {
      final end = candidate.at + window;
      var score = 0.0;

      for (final peak in found) {
        if (peak.at < candidate.at) continue;
        if (peak.at > end) break;
        score += peak.strength;
      }

      if (score > bestScore) {
        bestScore = score;
        bestStart = candidate.at;
      }
    }

    final lead = Duration(milliseconds: leadInMs);
    return bestStart > lead ? bestStart - lead : Duration.zero;
  }

  /// The low-frequency rumble over time, 0-1.
  ///
  /// Used as a floor the strip sits at between flashes, so a long roll keeps
  /// the cloud alive instead of leaving it dark between cracks.
  List<double> rumbleTrack() =>
      frames.map((f) => f.low.clamp(0.0, 1.0)).toList();

  /// Where the recording is at its loudest overall.
  Duration get loudestAt {
    if (frames.isEmpty) return Duration.zero;

    var bestIndex = 0;
    var best = frames[0].total;
    for (var i = 1; i < frames.length; i++) {
      if (frames[i].total > best) {
        best = frames[i].total;
        bestIndex = i;
      }
    }
    return Duration(milliseconds: bestIndex * frameMs);
  }
}

@immutable
class EnvelopePeak {
  const EnvelopePeak({
    required this.at,
    required this.strength,
    required this.amplitude,
    required this.brightness,
  });

  /// Offset from the start of the recording.
  final Duration at;

  /// How sharp the onset was, 0-1, relative to the strongest in the recording.
  final double strength;

  /// Overall loudness at this moment, 0-1.
  final double amplitude;

  /// How far toward the sharp end of the spectrum this moment sits, 0-1.
  /// A crack is near 1, a rumble near 0.
  final double brightness;

  @override
  String toString() => 'EnvelopePeak(${at.inMilliseconds}ms, '
      'strength ${strength.toStringAsFixed(2)}, '
      'bright ${brightness.toStringAsFixed(2)})';
}

/// Decodes each thunder sample and analyses its spectrum.
///
/// None of this happens in real time. A BLE link cannot react to audio as it
/// plays, so the recording is analysed up front and the light scheduled against
/// the result.
class ThunderEnvelopeStore extends ChangeNotifier {
  ThunderEnvelopeStore({this.frameMs = 20});

  /// Resolution of the stored envelope. Finer than the link can ever act on,
  /// which leaves the peak picker room to choose.
  final int frameMs;

  /// Analysis sample rate. Thunder has nothing above a few kHz worth tracking,
  /// and decoding to mono at this rate keeps the FFT work small.
  static const int analysisSampleRate = 22050;

  static const int fftSize = 1024;

  final Map<ThunderDistance, ThunderEnvelope> _cache = {};
  final Set<ThunderDistance> _failed = {};

  bool _analysing = false;
  bool get isAnalysing => _analysing;

  ThunderEnvelope? forDistance(ThunderDistance distance) => _cache[distance];
  bool hasEnvelope(ThunderDistance distance) => _cache.containsKey(distance);
  bool failedFor(ThunderDistance distance) => _failed.contains(distance);

  int get analysedCount => _cache.length;

  /// Analyses every bundled sample. Safe to call more than once; already
  /// analysed samples are skipped.
  Future<void> analyseAll() async {
    if (_analysing) return;
    _analysing = true;
    notifyListeners();

    try {
      for (final distance in ThunderDistance.values) {
        if (_cache.containsKey(distance)) continue;
        await _analyse(distance);
      }
    } finally {
      _analysing = false;
      notifyListeners();
    }
  }

  Future<void> _analyse(ThunderDistance distance) async {
    try {
      final temp = await getTemporaryDirectory();

      // The decoder works on files and the samples ship as assets, so the
      // asset is written out once before it can be decoded.
      final source = File('${temp.path}/${distance.name}_src.mp3');
      if (!await source.exists()) {
        final bytes = await rootBundle.load(distance.asset);
        await source.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      }

      final wavPath = '${temp.path}/${distance.name}_analysis.wav';

      await AudioDecoder.convertToWav(
        source.path,
        wavPath,
        sampleRate: analysisSampleRate,
        channels: 1,
        bitDepth: 16,
      );

      final pcm = WavReader.parse(await File(wavPath).readAsBytes());
      _cache[distance] = analyse(pcm, frameMs: frameMs, fftSize: fftSize);
      _failed.remove(distance);

      final envelope = _cache[distance]!;
      final all = envelope.peaks(minGapMs: 60);
      final firstNine = all
          .where((p) => p.at <= const Duration(seconds: 9))
          .toList();

      debugPrint(
        '[Envelope] ${distance.name}: '
        '${envelope.frames.length} frames, '
        '${pcm.duration.inMilliseconds}ms, '
        'loudest at ${envelope.loudestAt.inMilliseconds}ms, '
        'peaks total=${all.length} in-first-9s=${firstNine.length}',
      );

      if (firstNine.isEmpty && all.isNotEmpty) {
        debugPrint(
          '[Envelope] ${distance.name}: no thunder near the start; '
          'the strike will be located at ${envelope.strikeStart()}',
        );
      }
    } catch (e) {
      debugPrint('[Envelope] analysis failed for ${distance.name}: $e');
      _failed.add(distance);
    }
    notifyListeners();
  }

  /// Turns PCM into a banded envelope. Pure, so it can be tested without a
  /// device or a decoder.
  static ThunderEnvelope analyse(
    PcmAudio pcm, {
    int frameMs = 20,
    int fftSize = 1024,
  }) {
    if (pcm.samples.isEmpty || pcm.sampleRate <= 0) {
      return ThunderEnvelope(
        frames: const [],
        frameMs: frameMs,
        duration: Duration.zero,
      );
    }

    final fft = Fft(fftSize);
    final hop = max(1, pcm.sampleRate * frameMs ~/ 1000);

    final lowStart = fft.binFor(20, pcm.sampleRate);
    final lowEnd = fft.binFor(250, pcm.sampleRate);
    final midEnd = fft.binFor(2000, pcm.sampleRate);
    final highEnd = fft.binFor(8000, pcm.sampleRate);

    final frames = <SpectralFrame>[];
    var peakLow = 0.0;
    var peakMid = 0.0;
    var peakHigh = 0.0;

    final window = Float64List(fftSize);

    for (var start = 0; start < pcm.samples.length; start += hop) {
      final count = min(fftSize, pcm.samples.length - start);
      if (count <= 0) break;

      window.fillRange(0, fftSize, 0);
      for (var i = 0; i < count; i++) {
        window[i] = pcm.samples[start + i];
      }

      final magnitudes = fft.magnitudes(window);

      final low = _bandEnergy(magnitudes, lowStart, lowEnd);
      final mid = _bandEnergy(magnitudes, lowEnd, midEnd);
      final high = _bandEnergy(magnitudes, midEnd, highEnd);

      peakLow = max(peakLow, low);
      peakMid = max(peakMid, mid);
      peakHigh = max(peakHigh, high);

      frames.add(SpectralFrame(low: low, mid: mid, high: high));
    }

    // Each band is normalised against its own loudest moment. Without this the
    // low band swamps the others on every recording, because thunder simply
    // has far more energy down there, and the sharp detail would never surface.
    final normalised = [
      for (final frame in frames)
        SpectralFrame(
          low: peakLow > 0 ? (frame.low / peakLow).clamp(0.0, 1.0) : 0.0,
          mid: peakMid > 0 ? (frame.mid / peakMid).clamp(0.0, 1.0) : 0.0,
          high: peakHigh > 0 ? (frame.high / peakHigh).clamp(0.0, 1.0) : 0.0,
        ),
    ];

    return ThunderEnvelope(
      frames: normalised,
      frameMs: frameMs,
      duration: pcm.duration,
    );
  }

  static double _bandEnergy(Float64List magnitudes, int from, int to) {
    if (to <= from) return 0;
    var sum = 0.0;
    for (var i = from; i < to && i < magnitudes.length; i++) {
      sum += magnitudes[i];
    }
    return sum / (to - from);
  }
}
