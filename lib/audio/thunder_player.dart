import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'sound_pack.dart';

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
/// Supports both bundled assets and custom imported sound packs.
class ThunderPlayer extends ChangeNotifier {
  final Map<ThunderDistance, AudioPlayer> _players = {};
  final Map<ThunderDistance, StreamSubscription> _stateSubs = {};
  final Set<Timer> _pending = {};
  final Set<ThunderDistance> _failed = {};

  SoundPack _currentPack = SoundPack.defaultPack;
  ThunderDistance? _activePlayingDistance;
  bool _disposed = false;

  SoundPack get currentPack => _currentPack;
  ThunderDistance? get activePlayingDistance => _activePlayingDistance;

  bool get isReady => _players.length == ThunderDistance.values.length;
  bool get allFailed => _failed.length == ThunderDistance.values.length;
  Set<ThunderDistance> get failedAssets => Set.unmodifiable(_failed);

  /// True if any thunder player is currently outputting sound.
  bool get isPlaying => _players.values.any((p) => p.playing);

  /// Decodes all three samples up front for the active sound pack.
  Future<void> load() async {
    await loadPack(_currentPack);
  }

  /// Reloads audio players with samples from [pack].
  Future<void> loadPack(SoundPack pack) async {
    if (_disposed) return;
    _currentPack = pack;

    // Clean up existing players
    for (final sub in _stateSubs.values) {
      await sub.cancel();
    }
    _stateSubs.clear();

    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
    _failed.clear();

    await Future.wait(ThunderDistance.values.map(_loadOne));
    notifyListeners();
  }

  Future<void> _loadOne(ThunderDistance distance) async {
    if (_disposed) return;
    final player = AudioPlayer();
    final path = _currentPack.audioPathFor(distance);
    final isAsset = _currentPack.isAssetFor(distance);

    try {
      if (isAsset) {
        await player.setAsset(path);
      } else {
        await player.setFilePath(path);
      }

      _players[distance] = player;
      _failed.remove(distance);

      // Listen to playing state to notify visualizer widgets
      _stateSubs[distance] = player.playerStateStream.listen((state) {
        if (state.playing && state.processingState != ProcessingState.completed) {
          _activePlayingDistance = distance;
        } else if (_activePlayingDistance == distance && !state.playing) {
          _activePlayingDistance = null;
        }
        notifyListeners();
      });
    } catch (e) {
      _failed.add(distance);
      debugPrint('[StromSync] failed to load audio from $path: $e');
      await player.dispose();
    }
  }

  /// Schedules [distance]'s sample to play in [delay].
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
      _activePlayingDistance = distance;
      notifyListeners();
      await player.seek(Duration.zero);
      await player.play();
    } catch (e) {
      debugPrint('[StromSync] playback failed for $distance: $e');
    }
  }

  /// Cancels any scheduled claps and silences anything already sounding.
  Future<void> stopAll() async {
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
    _activePlayingDistance = null;
    await Future.wait(_players.values.map((p) => p.stop()));
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
    for (final sub in _stateSubs.values) {
      sub.cancel();
    }
    _stateSubs.clear();
    for (final player in _players.values) {
      player.dispose();
    }
    _players.clear();
    super.dispose();
  }
}
