import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Loops a rain bed under everything else.
///
/// Kept separate from [ThunderPlayer] because it is a different kind of sound:
/// one continuous loop that runs for as long as the weather is on, rather than
/// a one-shot scheduled against a flash.
class RainPlayer extends ChangeNotifier {
  static const String asset = 'assets/audio/rain.mp3';

  final AudioPlayer _player = AudioPlayer();

  bool _loaded = false;
  bool _playing = false;
  bool _disposed = false;
  String? _error;

  bool get isPlaying => _playing;

  /// True when the asset could not be decoded. The glow still runs in that
  /// case; only the sound is missing.
  bool get failed => _error != null;
  String? get error => _error;

  Future<void> load() async {
    if (_loaded || _disposed) return;

    try {
      await _player.setAsset(asset);
      await _player.setLoopMode(LoopMode.one);
      _loaded = true;
      _error = null;
    } catch (e) {
      // A missing rain file is an expected state, not a crash: the app ships
      // without one and the user drops their own in.
      _error = 'no rain sample at $asset';
      debugPrint('[Rain] $_error ($e)');
    }
    notifyListeners();
  }

  Future<void> start({double volume = 0.7}) async {
    if (_disposed) return;
    await load();
    if (!_loaded) return;

    try {
      await _player.setVolume(volume.clamp(0.0, 1.0));
      await _player.play();
      _playing = true;
    } catch (e) {
      debugPrint('[Rain] playback failed: $e');
    }
    notifyListeners();
  }

  Future<void> stop() async {
    if (_disposed || !_loaded) {
      _playing = false;
      notifyListeners();
      return;
    }

    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[Rain] stop failed: $e');
    }
    _playing = false;
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    if (_disposed || !_loaded) return;
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _disposed = true;
    _player.dispose();
    super.dispose();
  }
}
