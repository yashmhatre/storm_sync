import 'dart:math';

import 'package:flutter/foundation.dart';

import '../audio/thunder_envelope.dart';
import '../thunder/bolt_segments.dart';

/// Renders a strike as actual pixels.
///
/// Everything the BLE controllers made impossible is straightforward here,
/// because the app decides what every LED shows rather than asking a controller
/// to run one of its built-in effects:
///
/// * a bolt lights the LEDs of a real bolt shape, and nothing between them
/// * it is blue-white, because colour is per pixel rather than baked into an
///   effect number
/// * strokes decay on a proper exponential at frame rate, instead of two or
///   three brightness writes
/// * the whole strip can glow dimly *while* a bolt burns bright on part of it
///
/// The renderer is pure: it turns a time offset into a frame. Nothing here
/// touches the network, so the whole look can be tested without hardware.
@immutable
class LightningRenderer {
  const LightningRenderer({
    required this.pixelCount,
    this.glow = const PixelColor(6, 12, 26),
    this.bolt = const PixelColor(170, 205, 255),
    this.gamma = 2.2,
  });

  final int pixelCount;

  /// The standing storm glow the whole strip sits at.
  final PixelColor glow;

  /// A lightning channel is blue-white: blue highest, green below it, red
  /// lowest.
  final PixelColor bolt;

  /// LEDs are linear in duty cycle but the eye is not, so levels are gamma
  /// corrected before being written. Without this a decay tail collapses to
  /// nothing almost immediately.
  final double gamma;

  /// Renders one frame.
  ///
  /// [strokes] are the return strokes, [at] is the time since the strike
  /// started, and [rumble] is the current low-band level, which lifts the whole
  /// strip slightly while the thunder rolls.
  Uint8List frame({
    required Duration at,
    required List<Stroke> strokes,
    double rumble = 0,
    double glowLevel = 0.10,
  }) {
    final out = Uint8List(pixelCount * 3);

    // Base: the storm sky, lifted a little by whatever is rumbling.
    final baseLevel = (glowLevel + rumble * 0.25).clamp(0.0, 1.0);

    for (var i = 0; i < pixelCount; i++) {
      _write(out, i, glow, baseLevel);
    }

    // Then the strokes, brightest wins, so overlapping bolts do not darken
    // each other.
    for (final stroke in strokes) {
      final level = stroke.levelAt(at);
      if (level <= 0) continue;

      final from = stroke.startPixel.clamp(0, pixelCount - 1);
      final to = stroke.endPixel.clamp(0, pixelCount - 1);
      final lo = min(from, to);
      final hi = max(from, to);

      for (var i = lo; i <= hi; i++) {
        // Taper the ends so a bolt does not stop dead at a pixel boundary.
        final span = (hi - lo).clamp(1, pixelCount);
        final edge = min(i - lo, hi - i) / span;
        final shaped = level * (0.35 + 0.65 * min(1.0, edge * 6));

        _writeMax(out, i, bolt, shaped);
      }
    }

    return out;
  }

  void _write(Uint8List out, int index, PixelColor colour, double level) {
    final l = _gamma(level);
    final at = index * 3;
    out[at] = (colour.r * l).round().clamp(0, 255);
    out[at + 1] = (colour.g * l).round().clamp(0, 255);
    out[at + 2] = (colour.b * l).round().clamp(0, 255);
  }

  void _writeMax(Uint8List out, int index, PixelColor colour, double level) {
    final l = _gamma(level);
    final at = index * 3;
    final r = (colour.r * l).round().clamp(0, 255);
    final g = (colour.g * l).round().clamp(0, 255);
    final b = (colour.b * l).round().clamp(0, 255);

    if (r > out[at]) out[at] = r;
    if (g > out[at + 1]) out[at + 1] = g;
    if (b > out[at + 2]) out[at + 2] = b;
  }

  double _gamma(double level) {
    final clamped = level.clamp(0.0, 1.0);
    if (clamped <= 0) return 0;
    return pow(clamped, gamma).toDouble();
  }
}

@immutable
class PixelColor {
  const PixelColor(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;
}

/// One return stroke down one bolt shape.
///
/// A real stroke rises in microseconds and decays over milliseconds, which is
/// why [levelAt] snaps to full and then falls away on an exponential rather
/// than stepping.
@immutable
class Stroke {
  const Stroke({
    required this.startPixel,
    required this.endPixel,
    required this.at,
    required this.peak,
    required this.decay,
  });

  final int startPixel;
  final int endPixel;

  /// When this stroke fires, relative to the start of the strike.
  final Duration at;

  /// 0-1.
  final double peak;

  /// Time to fall to roughly a third of peak.
  final Duration decay;

  double levelAt(Duration now) {
    final since = now - at;
    if (since.isNegative) return 0;

    final t = since.inMicroseconds / decay.inMicroseconds;
    if (t > 6) return 0;

    return peak * exp(-t);
  }

  /// When this stroke has faded far enough to stop drawing it.
  Duration get endsAt => at + decay * 6;
}

/// Builds the strokes for one strike.
///
/// Given the bolt shapes the strip is bent into and an analysed recording, this
/// picks which bolt fires and when each return stroke lands. The result is a
/// plain list of strokes the renderer can draw at any frame rate.
class StrikeComposer {
  StrikeComposer({Random? random}) : _random = random ?? Random();

  final Random _random;

  List<Stroke> compose({
    required List<BoltSegment> bolts,
    required int pixelCount,
    ThunderEnvelope? envelope,
    double energy = 1.0,
    int windowMs = 900,
  }) {
    // Pick a bolt shape, or a stretch of strip when none are defined.
    final int start;
    final int end;

    if (bolts.isNotEmpty) {
      final bolt = bolts[_random.nextInt(bolts.length)];
      start = bolt.startPixel;
      end = bolt.endPixel;
    } else {
      final length = 30 + _random.nextInt(21);
      start = _random.nextInt(max(1, pixelCount - length));
      end = start + length;
    }

    final strokes = <Stroke>[];

    // Stroke times come from the recording where there is one, so the light
    // and the thunder are the same event.
    final times = <Duration>[];

    if (envelope != null && !envelope.isEmpty) {
      final seek = envelope.strikeStart(windowMs: windowMs);
      final peaks = envelope
          .peaks(minGapMs: 25)
          .where((p) =>
              p.at >= seek && p.at <= seek + Duration(milliseconds: windowMs))
          .take(5)
          .toList();

      for (final peak in peaks) {
        times.add(peak.at - seek);
      }
    }

    if (times.isEmpty) {
      var cursor = Duration.zero;
      final count = 2 + _random.nextInt(3);
      for (var i = 0; i < count; i++) {
        times.add(cursor);
        cursor += Duration(milliseconds: 35 + _random.nextInt(75));
      }
    }

    var level = energy.clamp(0.0, 1.0);

    for (var i = 0; i < times.length; i++) {
      strokes.add(Stroke(
        startPixel: start,
        endPixel: end,
        at: times[i],
        peak: level,
        // Later strokes are shorter as well as dimmer.
        decay: Duration(milliseconds: 40 + _random.nextInt(60)),
      ));

      level *= 0.55 + _random.nextDouble() * 0.3;
    }

    return strokes;
  }
}
