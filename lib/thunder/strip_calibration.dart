import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Converts "where on the strip" into "how long to let a sweep run".
///
/// An SP621E cannot address a range of pixels. The only spatial control it
/// offers is a built-in effect that walks a lit block along the strip, so a
/// bolt is placed by starting that sweep, waiting, and then cutting to black.
/// Where the block has reached when the lights go out is what the eye reads as
/// the bolt's position.
///
/// That makes placement open-loop: nothing reports the block's real position,
/// so the mapping has to be measured once per strip. [traverseMsAtSpeed1] is
/// that measurement, and [calibrate] is how the UI records it.
@immutable
class StripCalibration {
  const StripCalibration({
    this.pixelCount = 288,
    this.traverseMsAtSpeed1 = 9000,
  });

  /// How many pixels the sweep crosses before wrapping. This is the strip
  /// length the controller is configured for, not the app's idea of it.
  final int pixelCount;

  /// Measured time for the lit block to travel the whole strip at speed 1.
  ///
  /// The default is a starting guess, not a fact. Run the calibration screen
  /// against the real strip before trusting placement.
  final int traverseMsAtSpeed1;

  static const String _pixelKey = 'strip_pixel_count';
  static const String _traverseKey = 'strip_traverse_ms_speed1';

  static const int minTraverseMs = 500;
  static const int maxTraverseMs = 60000;

  /// Time for a full traverse at [speed].
  ///
  /// The controller exposes speed as 1-10 with no documented unit, so this
  /// assumes travel time is inversely proportional to the speed setting. That
  /// holds well enough in the middle of the range; calibrate at the speed you
  /// actually use for strikes if you need the ends to be accurate.
  int traverseMs(int speed) {
    final s = speed.clamp(1, 10);
    return (traverseMsAtSpeed1 / s).round();
  }

  /// How long to let a sweep run so the block lands at [position], where 0.0
  /// is the start of the strip and 1.0 is the far end.
  Duration dwellForPosition(double position, int speed) {
    final clamped = position.clamp(0.0, 1.0);
    return Duration(milliseconds: (traverseMs(speed) * clamped).round());
  }

  /// The inverse, for the calibration screen: where a given dwell lands.
  double positionForDwell(Duration dwell, int speed) {
    final total = traverseMs(speed);
    if (total <= 0) return 0;
    return (dwell.inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// Approximate pixel index the block reaches at [position].
  int pixelForPosition(double position) =>
      (pixelCount * position.clamp(0.0, 1.0)).round();

  /// Builds a calibration from a stopwatch measurement: the user started a
  /// sweep at [speed] and reported [observed] as the time for one full lap.
  StripCalibration calibrate({required int speed, required Duration observed}) {
    final s = speed.clamp(1, 10);
    final scaled = (observed.inMilliseconds * s)
        .clamp(minTraverseMs, maxTraverseMs)
        .toInt();
    return copyWith(traverseMsAtSpeed1: scaled);
  }

  StripCalibration copyWith({int? pixelCount, int? traverseMsAtSpeed1}) {
    return StripCalibration(
      pixelCount: pixelCount ?? this.pixelCount,
      traverseMsAtSpeed1: traverseMsAtSpeed1 ?? this.traverseMsAtSpeed1,
    );
  }

  static Future<StripCalibration> load() async {
    final prefs = await SharedPreferences.getInstance();
    const fallback = StripCalibration();
    return StripCalibration(
      pixelCount: prefs.getInt(_pixelKey) ?? fallback.pixelCount,
      traverseMsAtSpeed1:
          prefs.getInt(_traverseKey) ?? fallback.traverseMsAtSpeed1,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_pixelKey, pixelCount);
    await prefs.setInt(_traverseKey, traverseMsAtSpeed1);
  }

  @override
  bool operator ==(Object other) =>
      other is StripCalibration &&
      other.pixelCount == pixelCount &&
      other.traverseMsAtSpeed1 == traverseMsAtSpeed1;

  @override
  int get hashCode => Object.hash(pixelCount, traverseMsAtSpeed1);
}

/// Holds the active calibration and notifies the UI when it is re-measured.
class StripCalibrationStore extends ChangeNotifier {
  StripCalibrationStore(this._value);

  StripCalibration _value;
  StripCalibration get value => _value;

  set value(StripCalibration next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
    // The in-memory value is authoritative for the UI; persistence can lag.
    unawaited(next.save());
  }

  static Future<StripCalibrationStore> load() async =>
      StripCalibrationStore(await StripCalibration.load());
}
