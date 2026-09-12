import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// What the strike engine needs from a controller, whatever protocol it speaks.
///
/// The two families this app drives are not equivalent. An SP621E runs an
/// addressable strip and can light part of it; a MELK drives a plain RGB run
/// and can only light all of it. Rather than pretend otherwise, the difference
/// is declared in [supportsSegments] and the fleet routes around it: colour and
/// brightness go to every controller, and segment work goes only to the ones
/// that can do it.
///
/// That split is what makes a mixed pair useful instead of awkward — the
/// addressable strip draws the bolt while the plain one flashes the sky, both
/// off the same timeline.
abstract class LedDevice implements Listenable {
  /// Short name for the UI, e.g. "SP621E" or "MELK-OT21".
  String get label;

  /// The controller this link is pointed at, or null when idle.
  String? get deviceId;

  bool get isConnected;

  /// True when the controller can light a chosen stretch of the strip.
  bool get supportsSegments;

  /// Measured cost of one acknowledged write, in milliseconds.
  int get measuredWriteMs;

  int get writesSent;
  int get writesSkipped;
  void resetWriteStats();

  /// Forgets what the controller was last told, so the next command is sent
  /// even if it matches.
  void invalidateShadow();

  Future<void> connect(BluetoothDevice device);
  Future<void> disconnect();

  Future<void> setPower(bool on);

  /// Master brightness, 0-255, whatever scale the wire format uses.
  Future<void> setBrightness(int level);

  Future<void> setColor(int r, int g, int b, {int? level});

  /// Lights a travelling block of [length] pixels.
  ///
  /// A controller with [supportsSegments] false has no way to do this and
  /// should leave the strip alone rather than approximating it — the fleet
  /// already keeps such devices in step through brightness and colour.
  Future<void> setSegment({
    required int effect,
    required int speed,
    required int length,
    required int brightness,
  });

  /// Waits for every queued write to drain.
  Future<void> flush();

  void dispose();
}
