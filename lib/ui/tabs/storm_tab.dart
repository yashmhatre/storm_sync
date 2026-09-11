import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/thunder_player.dart';
import '../../ble/storm_service.dart';
import '../../model/app_settings.dart';
import '../theme.dart';
import '../widgets/audio_waveform_visualizer.dart';

/// A trigger button: one BLE command plus, optionally, one thunder sample.
class _Trigger {
  const _Trigger({
    required this.label,
    required this.sublabel,
    required this.command,
    required this.distance,
    required this.icon,
  });

  final String label;
  final String sublabel;
  final String command;
  final ThunderDistance distance;
  final IconData icon;
}

/// Energy 30-255. Higher reads as closer, so the near bolt sits near the top
/// of the range and the far one at the 120 the brief calls for.
const List<_Trigger> _triggers = [
  _Trigger(
    label: 'STRIKE',
    sublabel: 'near / 230',
    command: 'STRIKE 230',
    distance: ThunderDistance.close,
    icon: Icons.bolt,
  ),
  _Trigger(
    label: 'STRIKE',
    sublabel: 'mid / 175',
    command: 'STRIKE 175',
    distance: ThunderDistance.mid,
    icon: Icons.bolt_outlined,
  ),
  _Trigger(
    label: 'STRIKE',
    sublabel: 'far / 120',
    command: 'STRIKE 120',
    distance: ThunderDistance.far,
    icon: Icons.bolt_outlined,
  ),
  _Trigger(
    label: 'SHEET',
    sublabel: 'flash behind cloud',
    command: 'SHEET',
    distance: ThunderDistance.far,
    icon: Icons.cloud_outlined,
  ),
];

/// Modes and one-shot triggers, plus the speaker-latency trim that keeps the
/// clap landing where you want it relative to the flash.
class StormTab extends StatelessWidget {
  const StormTab({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<StormService>();
    final enabled = service.isConnected;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _SectionLabel('Mode'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ModeButton(
                label: 'GLOW',
                icon: Icons.wb_twilight,
                active: service.mode == 'GLOW',
                enabled: enabled,
                onPressed: () => service.setMode('GLOW'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeButton(
                label: 'STORM',
                icon: Icons.thunderstorm_outlined,
                active: service.mode == 'STORM',
                enabled: enabled,
                onPressed: () => service.setMode('STORM'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeButton(
                label: 'OFF',
                icon: Icons.power_settings_new,
                active: service.mode == 'OFF',
                enabled: enabled,
                onPressed: () => service.setMode('OFF'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const AudioWaveformVisualizer(),
        const SizedBox(height: 24),
        _SectionLabel('Trigger'),
        const SizedBox(height: 10),
        for (final trigger in _triggers) ...[
          _TriggerButton(trigger: trigger, enabled: enabled),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 18),
        const _AudioTimingCard(),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 24),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ],
    );

    return SizedBox(
      height: 84,
      child: active
          ? FilledButton(
              onPressed: enabled ? onPressed : null,
              child: child,
            )
          : OutlinedButton(
              onPressed: enabled ? onPressed : null,
              child: child,
            ),
    );
  }
}

/// Fires the light immediately, then schedules the matching sample.
///
/// The order matters and is the whole point: outdoors the flash reaches you
/// first, so the BLE write goes out before anything is queued for audio.
class _TriggerButton extends StatelessWidget {
  const _TriggerButton({required this.trigger, required this.enabled});

  final _Trigger trigger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<AppSettings>();
    final delay = settings.audioDelayFor(trigger.distance.distanceDelayMs);

    return SizedBox(
      height: 76,
      child: FilledButton.tonal(
        onPressed: enabled
            ? () {
                // Read without listening: this runs from a callback, not build.
                final service = context.read<StormService>();
                final thunder = context.read<ThunderPlayer>();

                service.send(trigger.command);
                thunder.playAfter(trigger.distance, delay);
              }
            : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Row(
          children: [
            Icon(trigger.icon, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    trigger.label,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    trigger.sublabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '+${delay.inMilliseconds} ms',
                  style: kMonoStyle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  trigger.distance.label.toLowerCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioTimingCard extends StatelessWidget {
  const _AudioTimingCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<AppSettings>();
    final thunder = context.read<ThunderPlayer>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speaker_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Speaker latency',
                      style: theme.textTheme.titleSmall),
                ),
                Text(
                  '${settings.speakerLatencyMs} ms',
                  style: kMonoStyle.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            Text(
              'Subtracted from the distance delay so the clap lands on time. '
              'Raise it if the thunder arrives late.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            Slider(
              min: AppSettings.minSpeakerLatencyMs.toDouble(),
              max: AppSettings.maxSpeakerLatencyMs.toDouble(),
              divisions: (AppSettings.maxSpeakerLatencyMs -
                      AppSettings.minSpeakerLatencyMs) ~/
                  10,
              value: settings.speakerLatencyMs.toDouble(),
              label: '${settings.speakerLatencyMs} ms',
              onChanged: (v) => settings.speakerLatencyMs = v.round(),
            ),
            if (thunder.failedAssets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: Color(0xFFF2CE7A)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Could not load: '
                        '${thunder.failedAssets.map((d) => d.label).join(', ')}. '
                        'Those triggers still fire the light, silently.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFF2CE7A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
