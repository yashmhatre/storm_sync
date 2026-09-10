import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-side preferences that survive a restart. Nothing here goes over BLE.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs)
      : _speakerLatencyMs =
            _prefs.getInt(_latencyKey) ?? defaultSpeakerLatencyMs;

  static const String _latencyKey = 'speaker_latency_ms';

  /// A typical A2DP Bluetooth speaker buffers about this much. Measure yours
  /// and adjust: the goal is flash and clap landing where you want them.
  static const int defaultSpeakerLatencyMs = 200;
  static const int minSpeakerLatencyMs = 0;
  static const int maxSpeakerLatencyMs = 600;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(prefs);
  }

  final SharedPreferences _prefs;

  int _speakerLatencyMs;

  /// How long the Bluetooth speaker lags behind the audio being handed to the
  /// OS. Subtracted from the physical distance delay so the clap lands on time.
  int get speakerLatencyMs => _speakerLatencyMs;

  set speakerLatencyMs(int value) {
    final clamped = value.clamp(minSpeakerLatencyMs, maxSpeakerLatencyMs);
    if (clamped == _speakerLatencyMs) return;
    _speakerLatencyMs = clamped;
    notifyListeners();
    // Fire and forget: the in-memory value is already authoritative for the UI.
    _prefs.setInt(_latencyKey, clamped);
  }

  /// The wait between firing the bolt and starting the sample.
  ///
  /// Clamped at zero: if the speaker lags more than the distance delay, the
  /// best we can do is start the sample immediately.
  Duration audioDelayFor(int distanceDelayMs) {
    final ms = distanceDelayMs - _speakerLatencyMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }
}
