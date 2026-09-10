import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// How far away the strike is meant to read. Picks both the sample and the
/// light-to-sound gap.
enum ThunderDistance {
  close(
    label: 'Close',
    asset: 'assets/audio/thunder_close.mp3',
    distanceDelayMs: 250,
  ),
  mid(
    label: 'Mid',
    asset: 'assets/audio/thunder_mid.mp3',
    distanceDelayMs: 1400,
  ),
  far(
    label: 'Far',
    asset: 'assets/audio/thunder_far.mp3',
    distanceDelayMs: 4200,
  );

  const ThunderDistance({
    required this.label,
    required this.asset,
    required this.distanceDelayMs,
  });

  final String label;
  final String asset;

  /// Time between the flash and the sound arriving, if the speaker were
  /// instantaneous. Roughly 340 m/s, so 4200 ms reads as about 1.4 km.
  final int distanceDelayMs;
}

/// Plays the thunder samples, on a delay, after the light has already fired.
///
/// This class knows nothing about how audio reaches the speaker. The Bluetooth
/// speaker is paired in the phone's system settings and Android routes output
/// to it; there is deliberately no speaker connection code anywhere in the app.
class ThunderPlayer {
  final Map<ThunderDistance, AudioPlayer> _players = {};
  final Set<Timer> _pending = {};

  /// Assets that failed to load, so the UI can say so instead of silently
  /// doing nothing.
  final Set<ThunderDistance> _failed = {};

  bool _disposed = false;

  bool get isReady => _players.length == ThunderDistance.values.length;

  /// True if every sample failed to load, which almost always means the
  /// placeholder assets were never replaced or the asset path is wrong.
  bool get allFailed => _failed.length == ThunderDistance.values.length;

  Set<ThunderDistance> get failedAssets => Set.unmodifiable(_failed);

  /// Decodes all three samples up front so a strike does not pay the load cost
  /// at the moment it needs to be on time.
  Future<void> load() async {
    await Future.wait(ThunderDistance.values.map(_loadOne));
  }

  Future<void> _loadOne(ThunderDistance distance) async {
    if (_disposed) return;
    final player = AudioPlayer();
    try {
      await player.setAsset(distance.asset);
      _players[distance] = player;
      _failed.remove(distance);
    } catch (e) {
      _failed.add(distance);
      debugPrint('[StromSync] failed to load ${distance.asset}: $e');
      await player.dispose();
    }
  }

  /// Schedules [distance]'s sample to play in [delay].
  ///
  /// The caller sends the BLE command first and calls this straight after, so
  /// the flash always leads the sound the way it does outdoors.
  void playAfter(ThunderDistance distance, Duration delay) {
    if (_disposed) return;

    if (delay <= Duration.zero) {
      unawaited(_playNow(distance));
      return;
    }

    late final Timer timer;
    timer = Timer(delay, () {
      _pending.remove(timer);
      unawaited(_playNow(distance));
    });
    _pending.add(timer);
  }

  Future<void> _playNow(ThunderDistance distance) async {
    if (_disposed) return;
    final player = _players[distance];
    if (player == null) return;

    try {
      // Restart from the top: pressing the button twice should re-trigger the
      // clap rather than be swallowed because the player is already playing.
      await player.seek(Duration.zero);
      await player.play();
    } catch (e) {
      debugPrint('[StromSync] playback failed for ${distance.asset}: $e');
    }
  }

  /// Cancels any scheduled claps and silences anything already sounding.
  Future<void> stopAll() async {
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
    await Future.wait(_players.values.map((p) => p.stop()));
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
    await Future.wait(_players.values.map((p) => p.dispose()));
    _players.clear();
  }
}
