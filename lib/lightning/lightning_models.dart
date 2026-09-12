enum LightningProfile {
  distant,
  normal,
  close,
  violent,
}

enum LightningPulseType {
  precursor,
  mainStroke,
  restrike,
  flicker,
  darkness,
  afterglow,
}

class LightningPulse {
  final LightningPulseType type;
  final double intensity; // 0.0 - 1.0
  final Duration duration;
  final int red;
  final int green;
  final int blue;

  const LightningPulse({
    required this.type,
    required this.intensity,
    required this.duration,
    required this.red,
    required this.green,
    required this.blue,
  });

  @override
  String toString() {
    return 'LightningPulse(type: $type, intensity: ${intensity.toStringAsFixed(2)}, duration: ${duration.inMilliseconds}ms)';
  }
}

class LightningSequence {
  final LightningProfile profile;
  final List<LightningPulse> pulses;
  final Duration thunderDelay;
  
  const LightningSequence({
    required this.profile,
    required this.pulses,
    required this.thunderDelay,
  });
  
  Duration get totalVisualDuration {
    return pulses.fold(Duration.zero, (prev, pulse) => prev + pulse.duration);
  }
}
