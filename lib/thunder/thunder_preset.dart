import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/thunder_player.dart';
import '../sp621e/sp621e_effects.dart';

/// The sound half of a thunder preset.
///
/// The sample is not just something played alongside the light: it is what
/// shapes the light. A close crack and a distant roll are different sounds and
/// different visual events, so the fields here feed straight into the strike
/// planner rather than sitting beside it.
@immutable
class ThunderSound {
  const ThunderSound({
    required this.distance,
    required this.sharpness,
    required this.energy,
    required this.rumbleTailMs,
    this.warmth = 10,
  });

  /// Chooses the sample and, with it, the physical flash-to-clap gap.
  final ThunderDistance distance;

  /// 0 is a long rolling rumble, 1 is a hard crack. Drives how many return
  /// strokes there are and how abrupt each one is.
  final double sharpness;

  /// 0 to 1, the peak brightness of the main stroke.
  final double energy;

  /// How long a dim afterglow lingers once the strokes are done, standing in
  /// for the rumble still rolling around the room.
  final int rumbleTailMs;

  /// How far the white leans warm, 0 to 40. Distant thunder scatters blue out
  /// of the light, so far strikes read warmer than close ones.
  final int warmth;

  /// The colour this sound strikes with, as an RGB triple.
  ///
  /// A lightning channel runs at tens of thousands of kelvin, so a close strike
  /// is blue-white: blue highest, green below it, red lowest. Equal red and
  /// blue reads as magenta on an RGB strip, which is the one thing lightning
  /// never looks like.
  ///
  /// Distance warms it. Air and rain scatter the blue out over a few
  /// kilometres, which is why a far strike glows amber rather than white.
  (int, int, int) get strikeColor {
    final t = (warmth.clamp(0, 40)) / 40.0;

    final r = (170 + (255 - 170) * t).round().clamp(0, 255);
    final g = (205 + (222 - 205) * t).round().clamp(0, 255);
    final b = (255 + (170 - 255) * t).round().clamp(0, 255);

    return (r, g, b);
  }

  ThunderSound copyWith({
    ThunderDistance? distance,
    double? sharpness,
    double? energy,
    int? rumbleTailMs,
    int? warmth,
  }) {
    return ThunderSound(
      distance: distance ?? this.distance,
      sharpness: sharpness ?? this.sharpness,
      energy: energy ?? this.energy,
      rumbleTailMs: rumbleTailMs ?? this.rumbleTailMs,
      warmth: warmth ?? this.warmth,
    );
  }

  Map<String, dynamic> toJson() => {
        'distance': distance.name,
        'sharpness': sharpness,
        'energy': energy,
        'rumbleTailMs': rumbleTailMs,
        'warmth': warmth,
      };

  static ThunderSound fromJson(Map<String, dynamic> json) {
    return ThunderSound(
      distance: ThunderDistance.values.firstWhere(
        (d) => d.name == json['distance'],
        orElse: () => ThunderDistance.mid,
      ),
      sharpness: (json['sharpness'] as num?)?.toDouble() ?? 0.5,
      energy: (json['energy'] as num?)?.toDouble() ?? 0.8,
      rumbleTailMs: (json['rumbleTailMs'] as num?)?.toInt() ?? 600,
      warmth: (json['warmth'] as num?)?.toInt() ?? 10,
    );
  }
}

/// The placement half of a thunder preset: where on the strip the bolt reads
/// as happening, and how wide it is.
///
/// On an SP621E none of this is addressed directly. [position] becomes a dwell
/// time via the strip calibration, [widthPixels] becomes the controller's
/// effect length, and [speed] becomes its effect speed.
@immutable
class StrikePlacement {
  const StrikePlacement({
    required this.position,
    required this.widthPixels,
    required this.speed,
    this.sweepEffect = Sp621eEffects.whiteSegmentSpin,
    this.floodOnImpact = true,
    this.boltId,
    this.randomBolt = false,
    this.followSound = false,
  });

  /// Drive the flashes from the recording's own loudness envelope instead of
  /// an invented flicker pattern. The bolt still fires first; everything after
  /// it follows the sound.
  final bool followSound;

  /// Which physical bolt shape this strike lights.
  ///
  /// When set, it overrides [position] and [widthPixels]: the bolt's own pixel
  /// range decides where the sweep is cut and how wide the lit block is. The
  /// raw position is only used when no bolt is targeted.
  final String? boltId;

  /// Pick a different bolt at random each time this preset fires. Overrides
  /// [boltId].
  final bool randomBolt;

  /// 0.0 at the start of the strip, 1.0 at the far end.
  final double position;

  /// Size of the travelling lit block, in pixels. The controller accepts
  /// 1 to 150.
  final int widthPixels;

  /// Controller effect speed, 1 to 10. Also sets how precisely [position] can
  /// be hit: a fast sweep crosses more strip per millisecond of timing error.
  final int speed;

  /// Which of the white sweeps carries the bolt.
  final int sweepEffect;

  /// Whether the main return stroke floods the whole strip with a solid flash.
  /// This is what sells a close strike, and what ruins a distant one.
  final bool floodOnImpact;

  StrikePlacement copyWith({
    double? position,
    int? widthPixels,
    int? speed,
    int? sweepEffect,
    bool? floodOnImpact,
    String? boltId,
    bool clearBolt = false,
    bool? randomBolt,
    bool? followSound,
  }) {
    return StrikePlacement(
      position: position ?? this.position,
      widthPixels: widthPixels ?? this.widthPixels,
      speed: speed ?? this.speed,
      sweepEffect: sweepEffect ?? this.sweepEffect,
      floodOnImpact: floodOnImpact ?? this.floodOnImpact,
      boltId: clearBolt ? null : (boltId ?? this.boltId),
      randomBolt: randomBolt ?? this.randomBolt,
      followSound: followSound ?? this.followSound,
    );
  }

  Map<String, dynamic> toJson() => {
        'position': position,
        'widthPixels': widthPixels,
        'speed': speed,
        'sweepEffect': sweepEffect,
        'floodOnImpact': floodOnImpact,
        'boltId': boltId,
        'randomBolt': randomBolt,
        'followSound': followSound,
      };

  static StrikePlacement fromJson(Map<String, dynamic> json) {
    return StrikePlacement(
      position: (json['position'] as num?)?.toDouble() ?? 0.5,
      widthPixels: (json['widthPixels'] as num?)?.toInt() ?? 48,
      speed: (json['speed'] as num?)?.toInt() ?? 8,
      sweepEffect:
          (json['sweepEffect'] as num?)?.toInt() ?? Sp621eEffects.whiteSegmentSpin,
      floodOnImpact: json['floodOnImpact'] as bool? ?? true,
      boltId: json['boltId'] as String?,
      randomBolt: json['randomBolt'] as bool? ?? false,
      followSound: json['followSound'] as bool? ?? false,
    );
  }
}

/// One named, editable thunder event: a sound and a placement.
@immutable
class ThunderPreset {
  const ThunderPreset({
    required this.id,
    required this.name,
    required this.sound,
    required this.placement,
  });

  final String id;
  final String name;
  final ThunderSound sound;
  final StrikePlacement placement;

  ThunderPreset copyWith({
    String? name,
    ThunderSound? sound,
    StrikePlacement? placement,
  }) {
    return ThunderPreset(
      id: id,
      name: name ?? this.name,
      sound: sound ?? this.sound,
      placement: placement ?? this.placement,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sound': sound.toJson(),
        'placement': placement.toJson(),
      };

  static ThunderPreset fromJson(Map<String, dynamic> json) {
    return ThunderPreset(
      id: json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Untitled',
      sound: ThunderSound.fromJson(
        (json['sound'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      placement: StrikePlacement.fromJson(
        (json['placement'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  /// The starting set. Each one pairs a sound with the placement that suits
  /// it: distant thunder sits wide and slow with no flood, a close strike is
  /// narrow, fast and floods the room.
  static List<ThunderPreset> defaults() => [
        const ThunderPreset(
          id: 'distant-roll',
          name: 'Distant roll',
          sound: ThunderSound(
            distance: ThunderDistance.far,
            sharpness: 0.15,
            energy: 0.45,
            rumbleTailMs: 1400,
            warmth: 28,
          ),
          placement: StrikePlacement(
            position: 0.15,
            widthPixels: 110,
            speed: 4,
            sweepEffect: Sp621eEffects.whiteWave,
            floodOnImpact: false,
            boltId: 'bolt-1',
          ),
        ),
        const ThunderPreset(
          id: 'rolling-mid',
          name: 'Rolling thunder',
          sound: ThunderSound(
            distance: ThunderDistance.mid,
            sharpness: 0.45,
            energy: 0.7,
            rumbleTailMs: 900,
            warmth: 16,
          ),
          placement: StrikePlacement(
            position: 0.4,
            widthPixels: 70,
            speed: 6,
            sweepEffect: Sp621eEffects.whiteSegmentSpin,
            floodOnImpact: true,
            boltId: 'bolt-2',
          ),
        ),
        const ThunderPreset(
          id: 'near-crack',
          name: 'Nearby crack',
          sound: ThunderSound(
            distance: ThunderDistance.close,
            sharpness: 0.85,
            energy: 0.95,
            rumbleTailMs: 450,
            warmth: 4,
          ),
          placement: StrikePlacement(
            position: 0.65,
            widthPixels: 34,
            speed: 9,
            sweepEffect: Sp621eEffects.whiteComet,
            floodOnImpact: true,
            boltId: 'bolt-3',
          ),
        ),
        const ThunderPreset(
          id: 'overhead',
          name: 'Overhead strike',
          sound: ThunderSound(
            distance: ThunderDistance.close,
            sharpness: 1.0,
            energy: 1.0,
            rumbleTailMs: 300,
            warmth: 0,
          ),
          placement: StrikePlacement(
            position: 0.9,
            widthPixels: 22,
            speed: 10,
            sweepEffect: Sp621eEffects.whiteMeteor,
            floodOnImpact: true,
            randomBolt: true,
          ),
        ),
      ];
}

/// Persists the user's edited presets.
class ThunderPresetStore extends ChangeNotifier {
  ThunderPresetStore(this._presets);

  static const String _key = 'thunder_presets_v1';

  List<ThunderPreset> _presets;
  List<ThunderPreset> get presets => List.unmodifiable(_presets);

  static Future<ThunderPresetStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);

    if (raw == null) return ThunderPresetStore(ThunderPreset.defaults());

    try {
      final decoded = jsonDecode(raw) as List;
      final parsed = decoded
          .map((e) => ThunderPreset.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      // An empty stored list would leave the user with no way back.
      if (parsed.isEmpty) return ThunderPresetStore(ThunderPreset.defaults());
      return ThunderPresetStore(parsed);
    } catch (_) {
      return ThunderPresetStore(ThunderPreset.defaults());
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_presets.map((p) => p.toJson()).toList()),
    );
  }

  ThunderPreset? byId(String id) {
    for (final preset in _presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  Future<void> upsert(ThunderPreset preset) async {
    final index = _presets.indexWhere((p) => p.id == preset.id);
    if (index >= 0) {
      _presets[index] = preset;
    } else {
      _presets.add(preset);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _presets.removeWhere((p) => p.id == id);
    if (_presets.isEmpty) _presets = ThunderPreset.defaults();
    notifyListeners();
    await _persist();
  }

  Future<void> restoreDefaults() async {
    _presets = ThunderPreset.defaults();
    notifyListeners();
    await _persist();
  }
}
