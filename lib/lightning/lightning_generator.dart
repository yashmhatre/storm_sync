import 'dart:math';
import 'lightning_models.dart';
import 'lightning_presets.dart';

class LightningGenerator {
  final Random _random;

  LightningGenerator({int? seed}) : _random = Random(seed);

  LightningSequence generate(LightningProfile profile) {
    final preset = LightningPresets.getPreset(profile);
    final List<LightningPulse> pulses = [];

    // Precursor
    if (_random.nextDouble() <= preset.precursorProbability) {
      final intensity = _randomDouble(preset.precursorBrightness);
      final durationMs = _randomInt(preset.precursorDurationMs);
      pulses.add(_createPulse(LightningPulseType.precursor, intensity, durationMs, preset.color));

      final darkMs = _randomInt(preset.precursorDarkGapMs);
      pulses.add(_createDarkness(darkMs));
    }

    // Main Stroke
    final mainIntensity = _randomDouble(preset.mainBrightness);
    final mainDurationMs = _randomInt(preset.mainDurationMs);
    pulses.add(_createPulse(LightningPulseType.mainStroke, mainIntensity, mainDurationMs, preset.color));

    // Restrikes
    final numRestrikes = _pickRestrikeCount(preset.restrikeCountProbabilities);
    
    for (int i = 0; i < numRestrikes; i++) {
      final gapMs = _triangularRandom(preset.interstrokeGapMs);
      pulses.add(_createDarkness(gapMs));

      final multiplier = _randomDouble(preset.restrikeBrightnessMultiplier);
      final intensity = (mainIntensity * multiplier).clamp(0.0, 1.0);
      final durationMs = _randomInt(preset.restrikeDurationMs);
      pulses.add(_createPulse(LightningPulseType.restrike, intensity, durationMs, preset.color));
    }

    // Micro-flicker
    if (_random.nextDouble() <= preset.flickerProbability) {
      final gapMs = _randomInt(preset.flickerGapMs);
      pulses.add(_createDarkness(gapMs));

      final intensity = _randomDouble(preset.flickerBrightness);
      final durationMs = _randomInt(preset.flickerDurationMs);
      pulses.add(_createPulse(LightningPulseType.flicker, intensity, durationMs, preset.color));
    }

    // Afterglow
    if (_random.nextDouble() <= preset.afterglowProbability) {
      // Small gap before afterglow if we didn't just have a flicker gap
      if (pulses.last.type != LightningPulseType.darkness) {
        pulses.add(_createDarkness(30));
      }
      final intensity = _randomDouble(preset.afterglowBrightness);
      final durationMs = _randomInt(preset.afterglowDurationMs);
      pulses.add(_createPulse(LightningPulseType.afterglow, intensity, durationMs, preset.color));
    }
    
    // Ensure it ends in darkness so the background can restore cleanly
    if (pulses.last.type != LightningPulseType.darkness) {
      pulses.add(_createDarkness(30));
    }

    // Thunder delay
    final thunderDelayMs = _randomInt(preset.thunderDelayMs);

    return LightningSequence(
      profile: profile,
      pulses: pulses,
      thunderDelay: Duration(milliseconds: thunderDelayMs),
    );
  }

  LightningPulse _createPulse(LightningPulseType type, double intensity, int durationMs, ColorPreset color) {
    // We apply gamma correction at the generator stage so that scheduling is raw RGB values
    // Gamma = 2.0 -> perceptual mapping
    final correctedIntensity = pow(intensity, 2.0).toDouble();

    // Randomize color within the preset range
    final rBase = _randomInt(color.r);
    final gBase = _randomInt(color.g);
    final bBase = _randomInt(color.b);

    final r = (rBase * correctedIntensity).round().clamp(0, 255);
    final g = (gBase * correctedIntensity).round().clamp(0, 255);
    final b = (bBase * correctedIntensity).round().clamp(0, 255);

    return LightningPulse(
      type: type,
      intensity: intensity,
      duration: Duration(milliseconds: durationMs),
      red: r,
      green: g,
      blue: b,
    );
  }

  LightningPulse _createDarkness(int durationMs) {
    return LightningPulse(
      type: LightningPulseType.darkness,
      intensity: 0.0,
      duration: Duration(milliseconds: durationMs),
      red: 0,
      green: 0,
      blue: 0,
    );
  }

  int _pickRestrikeCount(Map<int, double> probabilities) {
    final r = _random.nextDouble();
    double cumulative = 0.0;
    for (final entry in probabilities.entries) {
      cumulative += entry.value;
      if (r <= cumulative) return entry.key;
    }
    return 1; // Fallback
  }

  int _triangularRandom(TriangularRange<int> range) {
    final u = _random.nextDouble();
    final a = range.min.toDouble();
    final b = range.max.toDouble();
    final c = range.mode.toDouble();

    final fc = (c - a) / (b - a);
    if (u < fc) {
      return (a + sqrt(u * (b - a) * (c - a))).round();
    } else {
      return (b - sqrt((1 - u) * (b - a) * (b - c))).round();
    }
  }

  double _randomDouble(Range<double> range) {
    return range.min + _random.nextDouble() * (range.max - range.min);
  }

  int _randomInt(Range<int> range) {
    return range.min + _random.nextInt(range.max - range.min + 1);
  }
}
