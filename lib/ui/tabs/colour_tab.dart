import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ble/storm_service.dart';
import '../theme.dart';

/// RGB for the bolt (`COLOR`) and the cloud (`TINT`), with live swatches.
///
/// The firmware does not report its current colours, so these start at
/// app-side defaults and only become authoritative once you move a slider.
class ColourTab extends StatefulWidget {
  const ColourTab({super.key});

  @override
  State<ColourTab> createState() => _ColourTabState();
}

class _ColourTabState extends State<ColourTab>
    with AutomaticKeepAliveClientMixin {
  // Cold-white bolt against a deep blue cloud: the usual starting point.
  int _boltR = 255, _boltG = 250, _boltB = 235;
  int _tintR = 40, _tintG = 70, _tintB = 130;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final service = context.watch<StormService>();
    final enabled = service.isConnected;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _ColourCard(
          title: 'Bolt colour',
          command: 'COLOR',
          description: 'The lightning channel itself.',
          r: _boltR,
          g: _boltG,
          b: _boltB,
          enabled: enabled,
          presets: const {
            'Cold white': (255, 250, 235),
            'Blue-white': (200, 225, 255),
            'Violet': (200, 170, 255),
            'Warm': (255, 225, 170),
          },
          onChanged: (r, g, b, {required isFinal}) {
            setState(() {
              _boltR = r;
              _boltG = g;
              _boltB = b;
            });
            service.setColor(r, g, b, finalValue: isFinal);
          },
        ),
        const SizedBox(height: 16),
        _ColourCard(
          title: 'Cloud tint',
          command: 'TINT',
          description: 'The glow the cloud sits at between strikes.',
          r: _tintR,
          g: _tintG,
          b: _tintB,
          enabled: enabled,
          presets: const {
            'Storm blue': (40, 70, 130),
            'Slate': (70, 80, 95),
            'Ember': (150, 70, 30),
            'Deep teal': (20, 90, 95),
          },
          onChanged: (r, g, b, {required isFinal}) {
            setState(() {
              _tintR = r;
              _tintG = g;
              _tintB = b;
            });
            service.setTint(r, g, b, finalValue: isFinal);
          },
        ),
      ],
    );
  }
}

typedef _Rgb = (int, int, int);

class _ColourCard extends StatelessWidget {
  const _ColourCard({
    required this.title,
    required this.command,
    required this.description,
    required this.r,
    required this.g,
    required this.b,
    required this.enabled,
    required this.presets,
    required this.onChanged,
  });

  final String title;
  final String command;
  final String description;
  final int r;
  final int g;
  final int b;
  final bool enabled;
  final Map<String, _Rgb> presets;
  final void Function(int r, int g, int b, {required bool isFinal}) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = Color.fromARGB(255, r, g, b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Swatch(colour: colour, enabled: enabled),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$command $r $g $b',
                        style: kMonoStyle.copyWith(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ChannelSlider(
              label: 'R',
              value: r,
              tint: const Color(0xFFFF7A7A),
              enabled: enabled,
              onChanged: (v, {required isFinal}) =>
                  onChanged(v, g, b, isFinal: isFinal),
            ),
            _ChannelSlider(
              label: 'G',
              value: g,
              tint: const Color(0xFF7DE08A),
              enabled: enabled,
              onChanged: (v, {required isFinal}) =>
                  onChanged(r, v, b, isFinal: isFinal),
            ),
            _ChannelSlider(
              label: 'B',
              value: b,
              tint: const Color(0xFF7FA9FF),
              enabled: enabled,
              onChanged: (v, {required isFinal}) =>
                  onChanged(r, g, v, isFinal: isFinal),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in presets.entries)
                  ActionChip(
                    avatar: CircleAvatar(
                      backgroundColor: Color.fromARGB(
                        255,
                        entry.value.$1,
                        entry.value.$2,
                        entry.value.$3,
                      ),
                    ),
                    label: Text(entry.key),
                    onPressed: enabled
                        ? () => onChanged(
                              entry.value.$1,
                              entry.value.$2,
                              entry.value.$3,
                              // A preset is a single deliberate value, so it
                              // skips the throttle entirely.
                              isFinal: true,
                            )
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colour, required this.enabled});

  final Color colour;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: enabled ? colour : colour.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: colour.withValues(alpha: 0.45),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

/// One 0-255 channel. Same throttle contract as [ParamSlider]: continuous
/// updates during the drag, one guaranteed write on release.
class _ChannelSlider extends StatelessWidget {
  const _ChannelSlider({
    required this.label,
    required this.value,
    required this.tint,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color tint;
  final bool enabled;
  final void Function(int value, {required bool isFinal}) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            label,
            style: kMonoStyle.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: tint,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(activeTrackColor: tint),
            child: Slider(
              min: 0,
              max: 255,
              divisions: 255,
              value: value.toDouble(),
              label: '$value',
              onChanged: enabled
                  ? (v) => onChanged(v.round(), isFinal: false)
                  : null,
              onChangeEnd: enabled
                  ? (v) => onChanged(v.round(), isFinal: true)
                  : null,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: kMonoStyle.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }
}
