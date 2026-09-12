import 'package:flutter/foundation.dart';

import '../audio/thunder_player.dart';

/// One instruction in a strike, stamped with when it should happen relative to
/// the start of the strike.
///
/// A plan is built entirely before anything is written to the controller, so
/// the timeline can be inspected, tested and drawn without a light attached.
@immutable
sealed class StrikeStep {
  const StrikeStep({
    required this.at,
    required this.label,
    required this.writeCost,
  });

  /// Offset from the start of the strike.
  final Duration at;

  /// Short description, for the timeline view and the log.
  final String label;

  /// How many BLE writes this step really costs, given what the controller was
  /// already told by the step before it.
  ///
  /// The planner works this out as it goes rather than assuming the worst,
  /// because the difference decides how tightly steps can be packed: a sweep
  /// that changes every parameter costs four writes, while one that only
  /// changes brightness costs one.
  final int writeCost;
}

/// Runs one of the controller's white sweeps: a lit block travelling the
/// strip. This is the only step that produces movement, and therefore the only
/// one that carries placement.
class SweepStep extends StrikeStep {
  const SweepStep({
    required super.at,
    required super.label,
    required super.writeCost,
    required this.effect,
    required this.speed,
    required this.length,
    required this.brightness,
  });

  final int effect;
  final int speed;
  final int length;
  final int brightness;
}

/// Floods the whole strip with one solid colour. Used for the return stroke,
/// where the room lights up rather than a bolt travelling across it.
class FloodStep extends StrikeStep {
  const FloodStep({
    required super.at,
    required super.label,
    required super.writeCost,
    required this.r,
    required this.g,
    required this.b,
    required this.brightness,
  });

  final int r;
  final int g;
  final int b;
  final int brightness;
}

/// Changes nothing but the master brightness.
///
/// This is what makes a convincing flicker. Re-sending the colour or the effect
/// costs extra writes and drags each pulse out past the point where the eye
/// still reads it as one flickering bolt, so a restrike that keeps the previous
/// colour is expressed as one of these instead.
class FlickerStep extends StrikeStep {
  const FlickerStep({
    required super.at,
    required super.label,
    required this.brightness,
  }) : super(writeCost: 1);

  final int brightness;
}

/// Everything off.
class DarkStep extends StrikeStep {
  const DarkStep({required super.at, required super.label})
      : super(writeCost: 1);
}

/// A complete, executable strike.
@immutable
class StrikePlan {
  const StrikePlan({
    required this.steps,
    required this.mainStrokeAt,
    required this.thunderDelay,
    this.sample,
    required this.presetName,
    this.audioSeek = Duration.zero,
  });

  /// Where in the sample playback starts.
  ///
  /// Non-zero when the strike was located inside a long recording, so the
  /// sound and the light begin at the same moment in the storm rather than
  /// both starting at a silent file header.
  final Duration audioSeek;

  final List<StrikeStep> steps;

  /// When the main return stroke happens. The thunder is timed from here, not
  /// from the start of the plan, because the leader and precursor are not what
  /// makes the sound.
  final Duration mainStrokeAt;

  /// Gap between the main stroke and the sound arriving, before any correction
  /// for how far the speaker itself lags.
  final Duration thunderDelay;

  /// Null for a plan that makes no sound, such as the calibration sweep.
  final ThunderDistance? sample;
  final String presetName;

  /// When the visual part of the strike is over.
  Duration get visualDuration =>
      steps.isEmpty ? Duration.zero : steps.last.at;

  /// When the sound starts, relative to the start of the plan.
  Duration get audioAt => mainStrokeAt + thunderDelay;

  int get estimatedWrites =>
      steps.fold(0, (sum, step) => sum + step.writeCost);

  /// Writes per second the plan asks for on average. Past roughly 20 this
  /// stops being achievable over an acknowledged BLE link and steps will be
  /// dropped at run time.
  double get writesPerSecond {
    final ms = visualDuration.inMilliseconds;
    if (ms <= 0) return 0;
    return estimatedWrites * 1000 / ms;
  }

  @override
  String toString() => 'StrikePlan($presetName, ${steps.length} steps, '
      '${visualDuration.inMilliseconds}ms, $estimatedWrites writes)';
}
