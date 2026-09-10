/// The tunable parameters the StromSync firmware exposes over `SET`/`GET`/`LIST`.
///
/// Ranges here mirror the firmware's own clamps. Keeping them in one const list
/// means the tuning UI, the log and the reconnect-time refresh all agree on what
/// a legal value looks like.
library;

class ParamSpec {
  const ParamSpec({
    required this.key,
    required this.label,
    required this.min,
    required this.max,
    this.step = 1,
    this.description,
  });

  /// Wire name, e.g. `glow_floor` in `SET glow_floor 20`.
  final String key;

  /// Human label for the slider.
  final String label;

  final int min;
  final int max;

  /// Slider granularity. Wide millisecond ranges step coarsely so the slider
  /// stays draggable instead of offering ten thousand stops.
  final int step;

  final String? description;

  /// Number of discrete stops, for [Slider.divisions].
  int get divisions => ((max - min) / step).round().clamp(1, 1 << 20);

  int clampValue(int value) => value < min ? min : (value > max ? max : value);

  /// Snap an arbitrary slider position onto the nearest legal step.
  int snap(double raw) {
    final stepped = min + ((raw - min) / step).round() * step;
    return clampValue(stepped);
  }
}

/// Grouping only affects layout on the tuning tab.
class ParamGroup {
  const ParamGroup(this.title, this.params);
  final String title;
  final List<ParamSpec> params;
}

const List<ParamGroup> kParamGroups = [
  ParamGroup('Brightness & idle glow', [
    ParamSpec(
      key: 'bri',
      label: 'Master brightness',
      min: 0,
      max: 255,
      description: 'Overall output ceiling.',
    ),
    ParamSpec(
      key: 'glow_floor',
      label: 'Glow floor',
      min: 0,
      max: 80,
      description: 'Dimmest level the cloud settles to.',
    ),
    ParamSpec(
      key: 'glow_range',
      label: 'Glow range',
      min: 0,
      max: 80,
      description: 'How far the idle glow breathes above the floor.',
    ),
    ParamSpec(
      key: 'drift',
      label: 'Drift',
      min: 1,
      max: 8,
      description: 'Speed of the idle glow wander.',
    ),
    ParamSpec(
      key: 'noise_scale',
      label: 'Noise scale',
      min: 1,
      max: 40,
      description: 'Spatial size of the cloud texture.',
    ),
  ]),
  ParamGroup('Bolt shape', [
    ParamSpec(
      key: 'fork_max',
      label: 'Max forks',
      min: 0,
      max: 3,
      description: 'Branches split off the main channel.',
    ),
    ParamSpec(
      key: 'stroke_max',
      label: 'Max strokes',
      min: 1,
      max: 8,
      description: 'Return strokes per strike, the flicker count.',
    ),
    ParamSpec(
      key: 'fade_close',
      label: 'Fade (close)',
      min: 180,
      max: 250,
      description: 'Decay rate for high-energy bolts. Higher fades slower.',
    ),
    ParamSpec(
      key: 'fade_far',
      label: 'Fade (far)',
      min: 180,
      max: 250,
      description: 'Decay rate for low-energy bolts.',
    ),
    ParamSpec(
      key: 'sheet_ratio',
      label: 'Sheet ratio',
      min: 0,
      max: 255,
      description: 'Share of events that are sheet flashes rather than bolts.',
    ),
  ]),
  ParamGroup('Storm mode timing', [
    ParamSpec(
      key: 'rumble_rate',
      label: 'Rumble rate',
      min: 1,
      max: 20,
      description: 'Frequency of the low background rumble.',
    ),
    ParamSpec(
      key: 'storm_min',
      label: 'Storm gap min (ms)',
      min: 500,
      max: 10000,
      step: 100,
      description: 'Shortest wait between automatic events.',
    ),
    ParamSpec(
      key: 'storm_max',
      label: 'Storm gap max (ms)',
      min: 2000,
      max: 30000,
      step: 100,
      description: 'Longest wait between automatic events.',
    ),
  ]),
];

/// Flat view of every spec, in display order.
final List<ParamSpec> kAllParams = [
  for (final group in kParamGroups) ...group.params,
];

final Map<String, ParamSpec> kParamsByKey = {
  for (final spec in kAllParams) spec.key: spec,
};
