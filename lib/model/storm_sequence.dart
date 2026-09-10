import '../audio/thunder_player.dart';
import 'preset.dart';

/// One choreographed moment in a StormSequence.
class SequenceStep {
  const SequenceStep({
    required this.delayBeforeMs,
    required this.command,
    this.distance,
    this.boltColor,
    this.tintColor,
    this.label = '',
  });

  /// How long to wait before executing this step (milliseconds).
  final int delayBeforeMs;

  /// The BLE command to transmit, e.g. `STRIKE 240`, `SHEET`, `MODE GLOW`.
  final String command;

  /// Optional thunder audio sample to synchronize.
  final ThunderDistance? distance;

  /// Optional bolt colour override.
  final RgbColor? boltColor;

  /// Optional cloud tint colour override.
  final RgbColor? tintColor;

  /// Human-friendly description for timeline display.
  final String label;

  Map<String, dynamic> toJson() => {
        'delayBeforeMs': delayBeforeMs,
        'command': command,
        'distance': distance?.name,
        'boltColor': boltColor?.toJson(),
        'tintColor': tintColor?.toJson(),
        'label': label,
      };

  factory SequenceStep.fromJson(Map<String, dynamic> json) {
    final distName = json['distance'] as String?;
    ThunderDistance? dist;
    if (distName != null) {
      for (final d in ThunderDistance.values) {
        if (d.name == distName) {
          dist = d;
          break;
        }
      }
    }

    return SequenceStep(
      delayBeforeMs: (json['delayBeforeMs'] as num?)?.toInt() ?? 0,
      command: (json['command'] as String?) ?? 'SHEET',
      distance: dist,
      boltColor: json['boltColor'] != null
          ? RgbColor.fromJson(Map<String, dynamic>.from(json['boltColor'] as Map))
          : null,
      tintColor: json['tintColor'] != null
          ? RgbColor.fromJson(Map<String, dynamic>.from(json['tintColor'] as Map))
          : null,
      label: (json['label'] as String?) ?? '',
    );
  }
}

/// A choreographed multi-step storm sequence that automates lightning and thunder.
class StormSequence {
  const StormSequence({
    required this.id,
    required this.name,
    required this.description,
    required this.steps,
    this.isLooping = false,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final String description;
  final List<SequenceStep> steps;
  final bool isLooping;
  final bool isBuiltIn;

  /// Total duration of the sequence in milliseconds.
  int get totalDurationMs =>
      steps.fold<int>(0, (sum, step) => sum + step.delayBeforeMs);

  StormSequence copyWith({
    String? id,
    String? name,
    String? description,
    List<SequenceStep>? steps,
    bool? isLooping,
    bool? isBuiltIn,
  }) {
    return StormSequence(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      steps: steps ?? List<SequenceStep>.from(this.steps),
      isLooping: isLooping ?? this.isLooping,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'steps': steps.map((s) => s.toJson()).toList(),
        'isLooping': isLooping,
        'isBuiltIn': isBuiltIn,
      };

  factory StormSequence.fromJson(Map<String, dynamic> json) => StormSequence(
        id: json['id'] as String,
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        steps: (json['steps'] as List? ?? [])
            .map((s) => SequenceStep.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
        isLooping: (json['isLooping'] as bool?) ?? false,
        isBuiltIn: (json['isBuiltIn'] as bool?) ?? false,
      );

  /// Factory pre-choreographed sequences.
  static const List<StormSequence> builtInSequences = [
    StormSequence(
      id: 'approaching_tempest',
      name: 'Approaching Tempest',
      description: 'A storm building from distant soft rumbles into an overhead strike.',
      isLooping: false,
      isBuiltIn: true,
      steps: [
        SequenceStep(
          delayBeforeMs: 500,
          command: 'SHEET',
          distance: ThunderDistance.far,
          label: 'Distant sheet lightning behind the clouds',
        ),
        SequenceStep(
          delayBeforeMs: 3500,
          command: 'STRIKE 120',
          distance: ThunderDistance.far,
          label: 'First distant bolt strikes',
        ),
        SequenceStep(
          delayBeforeMs: 4000,
          command: 'STRIKE 180',
          distance: ThunderDistance.mid,
          label: 'Mid-range strike with growing rumble',
        ),
        SequenceStep(
          delayBeforeMs: 2500,
          command: 'STRIKE 240',
          distance: ThunderDistance.close,
          label: 'Violent close overhead bolt',
        ),
        SequenceStep(
          delayBeforeMs: 3000,
          command: 'MODE GLOW',
          label: 'Settle back into ambient glow',
        ),
      ],
    ),
    StormSequence(
      id: 'double_strike_burst',
      name: 'Twin Strike Outburst',
      description: 'A dramatic double bolt in rapid succession followed by trailing sheet.',
      isLooping: false,
      isBuiltIn: true,
      steps: [
        SequenceStep(
          delayBeforeMs: 600,
          command: 'STRIKE 220',
          distance: ThunderDistance.close,
          label: 'Primary strike',
        ),
        SequenceStep(
          delayBeforeMs: 900,
          command: 'STRIKE 245',
          distance: ThunderDistance.close,
          label: 'Immediate secondary flash',
        ),
        SequenceStep(
          delayBeforeMs: 3500,
          command: 'SHEET',
          distance: ThunderDistance.far,
          label: 'Trailing atmospheric rumble',
        ),
      ],
    ),
    StormSequence(
      id: 'night_pulse',
      name: 'Night Cloud Pulses',
      description: 'Continuous gentle sheet flashes for a relaxing night atmosphere.',
      isLooping: true,
      isBuiltIn: true,
      steps: [
        SequenceStep(
          delayBeforeMs: 1200,
          command: 'SHEET',
          distance: ThunderDistance.far,
          label: 'Soft purple cloud illumination',
        ),
        SequenceStep(
          delayBeforeMs: 4500,
          command: 'SHEET',
          distance: ThunderDistance.far,
          label: 'Secondary gentle pulse',
        ),
        SequenceStep(
          delayBeforeMs: 6000,
          command: 'STRIKE 90',
          distance: ThunderDistance.far,
          label: 'Distant low-energy bolt',
        ),
      ],
    ),
  ];
}

