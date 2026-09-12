import 'lightning_models.dart';

class Range<T extends num> {
  final T min;
  final T max;
  const Range(this.min, this.max);
}

class TriangularRange<T extends num> extends Range<T> {
  final T mode;
  const TriangularRange(super.min, this.mode, super.max);
}

class ColorPreset {
  final Range<int> r;
  final Range<int> g;
  final Range<int> b;
  const ColorPreset(this.r, this.g, this.b);
}

class ProfilePreset {
  // Precursor
  final double precursorProbability;
  final Range<double> precursorBrightness;
  final Range<int> precursorDurationMs;
  final Range<int> precursorDarkGapMs;

  // Main
  final Range<double> mainBrightness;
  final Range<int> mainDurationMs;
  
  // Restrikes
  final Map<int, double> restrikeCountProbabilities;
  final TriangularRange<int> interstrokeGapMs;
  final Range<int> restrikeDurationMs;
  final Range<double> restrikeBrightnessMultiplier;
  
  // Micro-flicker
  final double flickerProbability;
  final Range<double> flickerBrightness;
  final Range<int> flickerDurationMs;
  final Range<int> flickerGapMs;

  // Afterglow
  final double afterglowProbability;
  final Range<double> afterglowBrightness;
  final Range<int> afterglowDurationMs;

  // Global settings
  final Range<int> thunderDelayMs;
  final ColorPreset color;

  const ProfilePreset({
    required this.precursorProbability,
    required this.precursorBrightness,
    required this.precursorDurationMs,
    required this.precursorDarkGapMs,
    required this.mainBrightness,
    required this.mainDurationMs,
    required this.restrikeCountProbabilities,
    required this.interstrokeGapMs,
    required this.restrikeDurationMs,
    required this.restrikeBrightnessMultiplier,
    required this.flickerProbability,
    required this.flickerBrightness,
    required this.flickerDurationMs,
    required this.flickerGapMs,
    required this.afterglowProbability,
    required this.afterglowBrightness,
    required this.afterglowDurationMs,
    required this.thunderDelayMs,
    required this.color,
  });
}

class LightningPresets {
  static const coolWhite = ColorPreset(
    Range(210, 235), // R
    Range(225, 245), // G
    Range(245, 255), // B
  );

  static const mainWhite = ColorPreset(
    Range(235, 255), // R
    Range(245, 255), // G
    Range(250, 255), // B
  );

  static const distantWhite = ColorPreset(
    Range(190, 225), // R
    Range(215, 240), // G
    Range(240, 255), // B
  );

  // Normal profile preset
  static const normal = ProfilePreset(
    precursorProbability: 0.35,
    precursorBrightness: Range(0.18, 0.38),
    precursorDurationMs: Range(25, 45),
    precursorDarkGapMs: Range(30, 65),
    
    mainBrightness: Range(0.92, 1.00),
    mainDurationMs: Range(35, 65),
    
    restrikeCountProbabilities: {
      0: 0.12,
      1: 0.25,
      2: 0.32,
      3: 0.22,
      4: 0.09,
    },
    interstrokeGapMs: TriangularRange(30, 52, 85),
    restrikeDurationMs: Range(22, 48),
    restrikeBrightnessMultiplier: Range(0.45, 0.90),
    
    flickerProbability: 0.25,
    flickerBrightness: Range(0.20, 0.45),
    flickerDurationMs: Range(25, 32),
    flickerGapMs: Range(25, 50),
    
    afterglowProbability: 0.30,
    afterglowBrightness: Range(0.08, 0.18),
    afterglowDurationMs: Range(70, 160),
    
    thunderDelayMs: Range(600, 1800),
    color: mainWhite,
  );

  // Distant profile preset
  static const distant = ProfilePreset(
    precursorProbability: 0.10,
    precursorBrightness: Range(0.10, 0.25),
    precursorDurationMs: Range(25, 40),
    precursorDarkGapMs: Range(40, 80),
    
    mainBrightness: Range(0.55, 0.82),
    mainDurationMs: Range(40, 80),
    
    restrikeCountProbabilities: {
      0: 0.40,
      1: 0.40,
      2: 0.20,
      3: 0.0,
      4: 0.0,
    },
    interstrokeGapMs: TriangularRange(60, 90, 130),
    restrikeDurationMs: Range(30, 60),
    restrikeBrightnessMultiplier: Range(0.40, 0.80),
    
    flickerProbability: 0.10,
    flickerBrightness: Range(0.15, 0.30),
    flickerDurationMs: Range(25, 30),
    flickerGapMs: Range(40, 70),
    
    afterglowProbability: 0.60, // Frequent
    afterglowBrightness: Range(0.05, 0.12),
    afterglowDurationMs: Range(100, 250),
    
    thunderDelayMs: Range(1800, 4500),
    color: distantWhite,
  );

  // Close profile preset
  static const close = ProfilePreset(
    precursorProbability: 0.45,
    precursorBrightness: Range(0.25, 0.45),
    precursorDurationMs: Range(25, 45),
    precursorDarkGapMs: Range(25, 50),
    
    mainBrightness: Range(1.0, 1.0), // Always 100%
    mainDurationMs: Range(35, 60),
    
    restrikeCountProbabilities: {
      0: 0.0,
      1: 0.0,
      2: 0.30,
      3: 0.40,
      4: 0.30, // 2-4 restrikes
    },
    interstrokeGapMs: TriangularRange(28, 40, 55), // very fast
    restrikeDurationMs: Range(22, 45),
    restrikeBrightnessMultiplier: Range(0.60, 1.00), // very bright
    
    flickerProbability: 0.40,
    flickerBrightness: Range(0.30, 0.60),
    flickerDurationMs: Range(25, 35),
    flickerGapMs: Range(25, 40),
    
    afterglowProbability: 0.20,
    afterglowBrightness: Range(0.10, 0.20),
    afterglowDurationMs: Range(50, 120),
    
    thunderDelayMs: Range(120, 600),
    color: mainWhite,
  );

  // Violent profile preset (Storm Sync dramatic)
  static const violent = ProfilePreset(
    precursorProbability: 1.0, // We always have a precursor acting as the "moving white effect"
    precursorBrightness: Range(0.80, 1.00),
    precursorDurationMs: Range(80, 160),
    precursorDarkGapMs: Range(25, 45),
    
    mainBrightness: Range(1.0, 1.0),
    mainDurationMs: Range(40, 65),
    
    restrikeCountProbabilities: {
      0: 0.0,
      1: 0.0,
      2: 0.33,
      3: 0.34,
      4: 0.33,
    },
    interstrokeGapMs: TriangularRange(28, 40, 55),
    restrikeDurationMs: Range(25, 45),
    restrikeBrightnessMultiplier: Range(0.60, 1.00),
    
    flickerProbability: 0.50,
    flickerBrightness: Range(0.30, 0.60),
    flickerDurationMs: Range(25, 35),
    flickerGapMs: Range(25, 40),
    
    afterglowProbability: 0.30,
    afterglowBrightness: Range(0.10, 0.20),
    afterglowDurationMs: Range(50, 120),
    
    thunderDelayMs: Range(100, 900),
    color: mainWhite,
  );

  static ProfilePreset getPreset(LightningProfile profile) {
    switch (profile) {
      case LightningProfile.distant:
        return distant;
      case LightningProfile.normal:
        return normal;
      case LightningProfile.close:
        return close;
      case LightningProfile.violent:
        return violent;
    }
  }
}
