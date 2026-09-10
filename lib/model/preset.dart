import 'package:flutter/material.dart';

/// Representation of an RGB colour (0-255 per channel).
class RgbColor {
  const RgbColor(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  Color toColor() => Color.fromARGB(255, r, g, b);

  List<int> toList() => [r, g, b];

  Map<String, dynamic> toJson() => {'r': r, 'g': g, 'b': b};

  factory RgbColor.fromJson(Map<String, dynamic> json) => RgbColor(
        (json['r'] as num?)?.toInt() ?? 255,
        (json['g'] as num?)?.toInt() ?? 255,
        (json['b'] as num?)?.toInt() ?? 255,
      );

  factory RgbColor.fromList(List<int> list) => RgbColor(
        list.isNotEmpty ? list[0] : 255,
        list.length > 1 ? list[1] : 255,
        list.length > 2 ? list[2] : 255,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RgbColor &&
          runtimeType == other.runtimeType &&
          r == other.r &&
          g == other.g &&
          b == other.b;

  @override
  int get hashCode => Object.hash(r, g, b);
}

/// A complete snapshot of StromSync parameters, lighting colours, and audio timing.
class Preset {
  const Preset({
    required this.id,
    required this.name,
    required this.description,
    required this.parameters,
    required this.boltColor,
    required this.cloudTint,
    this.speakerLatencyMs = 200,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final String description;
  final Map<String, int> parameters;
  final RgbColor boltColor;
  final RgbColor cloudTint;
  final int speakerLatencyMs;
  final bool isBuiltIn;

  Preset copyWith({
    String? id,
    String? name,
    String? description,
    Map<String, int>? parameters,
    RgbColor? boltColor,
    RgbColor? cloudTint,
    int? speakerLatencyMs,
    bool? isBuiltIn,
  }) {
    return Preset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      parameters: parameters ?? Map<String, int>.from(this.parameters),
      boltColor: boltColor ?? this.boltColor,
      cloudTint: cloudTint ?? this.cloudTint,
      speakerLatencyMs: speakerLatencyMs ?? this.speakerLatencyMs,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'parameters': parameters,
        'boltColor': boltColor.toJson(),
        'cloudTint': cloudTint.toJson(),
        'speakerLatencyMs': speakerLatencyMs,
        'isBuiltIn': isBuiltIn,
      };

  factory Preset.fromJson(Map<String, dynamic> json) => Preset(
        id: json['id'] as String,
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        parameters: Map<String, int>.from(
          (json['parameters'] as Map? ?? {}).map(
            (k, v) => MapEntry(k.toString(), (v as num).toInt()),
          ),
        ),
        boltColor: RgbColor.fromJson(
          Map<String, dynamic>.from(json['boltColor'] as Map? ?? {}),
        ),
        cloudTint: RgbColor.fromJson(
          Map<String, dynamic>.from(json['cloudTint'] as Map? ?? {}),
        ),
        speakerLatencyMs: (json['speakerLatencyMs'] as num?)?.toInt() ?? 200,
        isBuiltIn: (json['isBuiltIn'] as bool?) ?? false,
      );

  /// Default factory presets ready out of the box.
  static const List<Preset> builtInPresets = [
    Preset(
      id: 'default_storm',
      name: 'Default Storm',
      description: 'Balanced firmware defaults for a realistic ambient thunderstorm.',
      parameters: {
        'bri': 200,
        'glow_floor': 10,
        'glow_range': 30,
        'drift': 3,
        'noise_scale': 15,
        'fork_max': 2,
        'stroke_max': 4,
        'fade_close': 210,
        'fade_far': 230,
        'sheet_ratio': 64,
        'rumble_rate': 6,
        'storm_min': 2000,
        'storm_max': 12000,
      },
      boltColor: RgbColor(255, 250, 235),
      cloudTint: RgbColor(40, 70, 130),
      speakerLatencyMs: 200,
      isBuiltIn: true,
    ),
    Preset(
      id: 'summer_heat',
      name: 'Summer Heat',
      description: 'Warm glowing cloud with frequent, soft silent sheet flashes.',
      parameters: {
        'bri': 160,
        'glow_floor': 25,
        'glow_range': 45,
        'drift': 2,
        'noise_scale': 10,
        'fork_max': 1,
        'stroke_max': 2,
        'fade_close': 240,
        'fade_far': 245,
        'sheet_ratio': 210,
        'rumble_rate': 2,
        'storm_min': 1500,
        'storm_max': 6000,
      },
      boltColor: RgbColor(255, 225, 170),
      cloudTint: RgbColor(120, 60, 20),
      speakerLatencyMs: 200,
      isBuiltIn: true,
    ),
    Preset(
      id: 'violent_gale',
      name: 'Violent Gale',
      description: 'Blinding close strikes, intense flickering, and heavy rumble.',
      parameters: {
        'bri': 255,
        'glow_floor': 5,
        'glow_range': 20,
        'drift': 6,
        'noise_scale': 25,
        'fork_max': 3,
        'stroke_max': 7,
        'fade_close': 190,
        'fade_far': 200,
        'sheet_ratio': 20,
        'rumble_rate': 16,
        'storm_min': 800,
        'storm_max': 4000,
      },
      boltColor: RgbColor(200, 225, 255),
      cloudTint: RgbColor(20, 30, 80),
      speakerLatencyMs: 200,
      isBuiltIn: true,
    ),
    Preset(
      id: 'alien_aurora',
      name: 'Alien Aurora',
      description: 'Surreal neon cyan bolts flickering against a deep violet cloud.',
      parameters: {
        'bri': 220,
        'glow_floor': 18,
        'glow_range': 50,
        'drift': 4,
        'noise_scale': 30,
        'fork_max': 3,
        'stroke_max': 5,
        'fade_close': 220,
        'fade_far': 235,
        'sheet_ratio': 90,
        'rumble_rate': 8,
        'storm_min': 2000,
        'storm_max': 9000,
      },
      boltColor: RgbColor(0, 255, 200),
      cloudTint: RgbColor(90, 20, 140),
      speakerLatencyMs: 200,
      isBuiltIn: true,
    ),
  ];
}

