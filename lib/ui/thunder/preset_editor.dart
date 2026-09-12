import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/thunder_envelope.dart';
import '../../audio/thunder_player.dart';
import '../../model/app_settings.dart';
import '../../sp621e/sp621e_effects.dart';
import '../../thunder/bolt_segments.dart';
import '../../thunder/strike_plan.dart';
import '../../thunder/strike_planner.dart';
import '../../thunder/strip_calibration.dart';
import '../../thunder/thunder_engine.dart';
import '../../thunder/thunder_preset.dart';
import 'strip_preview.dart';

/// Edits one thunder preset: the sound it makes, and where on the strip it
/// lands. Every change re-plans the strike, so the timeline and the strip
/// drawing below always show what the next tap will actually do.
class PresetEditor extends StatefulWidget {
  const PresetEditor({super.key, required this.preset, this.isNew = false});

  final ThunderPreset preset;
  final bool isNew;

  @override
  State<PresetEditor> createState() => _PresetEditorState();
}

class _PresetEditorState extends State<PresetEditor> {
  late ThunderPreset _draft = widget.preset;
  late final TextEditingController _name =
      TextEditingController(text: widget.preset.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _updateSound(ThunderSound Function(ThunderSound) change) {
    setState(() => _draft = _draft.copyWith(sound: change(_draft.sound)));
  }

  void _updatePlacement(StrikePlacement Function(StrikePlacement) change) {
    setState(
      () => _draft = _draft.copyWith(placement: change(_draft.placement)),
    );
  }

  /// What the sweep will really use, once a bolt target is taken into account.
  /// Mirrors the planner so the drawing cannot disagree with the strike.
  ({double position, int width}) _resolved(
    BoltSegmentStore bolts,
    StripCalibration calibration,
  ) {
    final placement = _draft.placement;

    if (placement.randomBolt && bolts.segments.isNotEmpty) {
      // A representative shape: the preview cannot show all of them at once.
      final bolt = bolts.segments.first;
      return (position: bolt.positionIn(calibration), width: bolt.length);
    }

    final bolt = bolts.byId(placement.boltId);
    if (bolt != null) {
      return (position: bolt.positionIn(calibration), width: bolt.length);
    }

    return (position: placement.position, width: placement.widthPixels);
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<ThunderEngine>();
    final calibration = context.watch<StripCalibrationStore>().value;
    final settings = context.watch<AppSettings>();
    final store = context.read<ThunderPresetStore>();
    final bolts = context.watch<BoltSegmentStore>();
    final envelopes = context.watch<ThunderEnvelopeStore>();

    final plan = engine.preview(_draft);
    final floor = StrikePlanner.minimumPlacement(
      _draft.placement.speed,
      calibration,
      writeCostMs: engine.measuredWriteMs,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New strike' : 'Edit strike'),
        actions: [
          if (!widget.isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await store.remove(_draft.id);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          TextButton(
            onPressed: () async {
              await store.upsert(_draft.copyWith(name: _name.text.trim()));
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // ---------------------------------------------------------------
          _SectionHeader(
            title: 'Sound',
            subtitle: 'What it sounds like decides what it looks like',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sample'),
                  const SizedBox(height: 8),
                  SegmentedButton<ThunderDistance>(
                    segments: [
                      for (final d in ThunderDistance.values)
                        ButtonSegment(value: d, label: Text(d.label)),
                    ],
                    selected: {_draft.sound.distance},
                    onSelectionChanged: (selection) => _updateSound(
                      (s) => s.copyWith(distance: selection.first),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Flash to clap: '
                    '${_draft.sound.distance.distanceDelayMs} ms, '
                    'less ${settings.speakerLatencyMs} ms of speaker lag',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Follow the sound'),
                    subtitle: Text(
                      envelopes.hasEnvelope(_draft.sound.distance)
                          ? 'Flashes come from the peaks in this recording, '
                              'not from the sliders below'
                          : envelopes.failedFor(_draft.sound.distance)
                              ? 'This sample could not be analysed; the '
                                  'sliders below are used instead'
                              : 'Analysing the sample…',
                    ),
                    value: _draft.placement.followSound,
                    onChanged: (v) =>
                        _updatePlacement((p) => p.copyWith(followSound: v)),
                  ),
                  if (_draft.placement.followSound)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Sharpness is ignored while this is on. Energy still '
                        'scales the overall brightness, and the bolt still '
                        'fires before the sound arrives.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  _Slider(
                    label: 'Sharpness',
                    hint: 'Rolling rumble to hard crack. Adds return strokes.',
                    value: _draft.sound.sharpness,
                    onChanged: (v) => _updateSound((s) => s.copyWith(sharpness: v)),
                    display: '${(_draft.sound.sharpness * 100).round()}%',
                  ),
                  _Slider(
                    label: 'Energy',
                    hint: 'Peak brightness of the main stroke.',
                    value: _draft.sound.energy,
                    onChanged: (v) => _updateSound((s) => s.copyWith(energy: v)),
                    display: '${(_draft.sound.energy * 100).round()}%',
                  ),
                  _Slider(
                    label: 'Warmth',
                    hint: 'Distant thunder reads warmer; close strikes are blue-white.',
                    value: _draft.sound.warmth / 40,
                    onChanged: (v) =>
                        _updateSound((s) => s.copyWith(warmth: (v * 40).round())),
                    display: '${_draft.sound.warmth}',
                  ),
                  _Slider(
                    label: 'Rumble tail',
                    hint: 'How long a dim glow holds while the sound rolls on.',
                    value: _draft.sound.rumbleTailMs / 3000,
                    onChanged: (v) => _updateSound(
                      (s) => s.copyWith(rumbleTailMs: (v * 3000).round()),
                    ),
                    display: '${_draft.sound.rumbleTailMs} ms',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ---------------------------------------------------------------
          _SectionHeader(
            title: 'Placement',
            subtitle: 'Where on the strip the bolt lands',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Target'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Free position'),
                        selected: _draft.placement.boltId == null &&
                            !_draft.placement.randomBolt,
                        onSelected: (_) => _updatePlacement(
                          (p) => p.copyWith(clearBolt: true, randomBolt: false),
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Random bolt'),
                        selected: _draft.placement.randomBolt,
                        onSelected: (_) => _updatePlacement(
                          (p) => p.copyWith(clearBolt: true, randomBolt: true),
                        ),
                      ),
                      for (final bolt in bolts.segments)
                        ChoiceChip(
                          label: Text(bolt.name),
                          selected: !_draft.placement.randomBolt &&
                              _draft.placement.boltId == bolt.id,
                          onSelected: (_) => _updatePlacement(
                            (p) => p.copyWith(
                              boltId: bolt.id,
                              randomBolt: false,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  StripPreview(
                    position: _resolved(bolts, calibration).position,
                    widthPixels: _resolved(bolts, calibration).width,
                    pixelCount: calibration.pixelCount,
                    brightness: _draft.sound.energy,
                    unreachableBelow: floor,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'About LED '
                    '${calibration.pixelForPosition(_draft.placement.position)} '
                    'of ${calibration.pixelCount}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  if (_draft.placement.position < floor)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Below ${(floor * 100).round()}% the sweep cannot be cut '
                        'short in time, so the bolt will land further along than '
                        'this. Raise the speed to reach nearer positions.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  if (_draft.placement.boltId != null ||
                      _draft.placement.randomBolt)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _draft.placement.randomBolt
                            ? 'A different bolt fires each time. Position and '
                                'width come from whichever shape is picked.'
                            : 'Position and width come from this bolt. Edit the '
                                'shape itself on the Bolts screen.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    )
                  else ...[
                  _Slider(
                    label: 'Position',
                    hint: 'Start of the strip to the far end.',
                    value: _draft.placement.position,
                    onChanged: (v) =>
                        _updatePlacement((p) => p.copyWith(position: v)),
                    display: '${(_draft.placement.position * 100).round()}%',
                  ),
                  _Slider(
                    label: 'Width',
                    hint: 'Size of the lit block, in LEDs.',
                    value: _draft.placement.widthPixels / 150,
                    onChanged: (v) => _updatePlacement(
                      (p) => p.copyWith(
                        widthPixels: (v * 150).round().clamp(1, 150),
                      ),
                    ),
                    display: '${_draft.placement.widthPixels} px',
                  ),
                  ],
                  _Slider(
                    label: 'Speed',
                    hint: 'How fast the block travels. Faster reaches nearer '
                        'positions, but places less precisely.',
                    value: (_draft.placement.speed - 1) / 9,
                    onChanged: (v) => _updatePlacement(
                      (p) => p.copyWith(
                        speed: (1 + v * 9).round().clamp(1, 10),
                      ),
                    ),
                    display: '${_draft.placement.speed}/10',
                  ),
                  const SizedBox(height: 8),
                  const Text('Bolt shape'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final id in Sp621eEffects.whiteSweeps)
                        ChoiceChip(
                          label: Text(
                            Sp621eEffects.byId(id)!.name.replaceAll('White ', ''),
                          ),
                          selected: _draft.placement.sweepEffect == id,
                          onSelected: (_) => _updatePlacement(
                            (p) => p.copyWith(sweepEffect: id),
                          ),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Flood the strip on impact'),
                    subtitle: const Text(
                      'Sells a close strike, spoils a distant one',
                    ),
                    value: _draft.placement.floodOnImpact,
                    onChanged: (v) =>
                        _updatePlacement((p) => p.copyWith(floodOnImpact: v)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ---------------------------------------------------------------
          _SectionHeader(
            title: 'Plan',
            subtitle: 'Blue is a moving sweep, white is a full-strip flash, '
                'the vertical line is the thunder',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StrikeTimeline(
                    total: plan.visualDuration,
                    audioAt:
                        plan.audioAt <= plan.visualDuration ? plan.audioAt : null,
                    marks: [
                      for (final step in plan.steps)
                        (
                          at: step.at,
                          intensity: switch (step) {
                            SweepStep() => step.brightness / 255,
                            FloodStep() => step.brightness / 255,
                            FlickerStep() => step.brightness / 255,
                            DarkStep() => 0.05,
                          },
                          sweep: step is SweepStep,
                          label: step.label,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${plan.steps.length} steps · '
                    '${plan.visualDuration.inMilliseconds} ms · '
                    '${plan.estimatedWrites} writes '
                    '(${plan.writesPerSecond.toStringAsFixed(1)}/s)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (plan.writesPerSecond > 20)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'That is more traffic than the link reliably carries. '
                        'Steps will be dropped to keep the sound in time.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: engine.isStriking
                        ? null
                        : () => engine.strike(
                              _draft.copyWith(name: _name.text.trim()),
                            ),
                    icon: const Icon(Icons.bolt),
                    label: const Text('Test strike'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    required this.display,
  });

  final String label;
  final String hint;
  final double value;
  final ValueChanged<double> onChanged;
  final String display;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                display,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                    ),
              ),
            ],
          ),
          Text(
            hint,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Slider(
            value: value.clamp(0.0, 1.0),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
