import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/rain_player.dart';
import '../../sp621e/sp621e_connection.dart';
import '../../sp621e/sp621e_fleet.dart';
import '../../thunder/thunder_engine.dart';
import 'bolts_screen.dart';
import 'connect_screen.dart';
import 'calibration_screen.dart';
import 'log_sheet.dart';

/// The one screen this app is for: fire thunder, or let it fire itself.
class ThunderHome extends StatelessWidget {
  const ThunderHome({super.key});

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<Sp621eFleet>();
    final connection = fleet.primary;
    final engine = context.watch<ThunderEngine>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          fleet.connectedCount > 1
              ? 'Thunder · ${fleet.connectedCount} strips'
              : 'Thunder',
        ),
        actions: [
          IconButton(
            tooltip: 'Bolt shapes',
            icon: const Icon(Icons.bolt),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BoltsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Calibrate strip',
            icon: const Icon(Icons.straighten),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CalibrationScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'BLE log',
            icon: const Icon(Icons.terminal),
            onPressed: () => showLogSheet(context),
          ),
          IconButton(
            tooltip: 'Add another controller',
            icon: const Icon(Icons.add_link),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ThunderConnectScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Disconnect all',
            icon: const Icon(Icons.link_off),
            onPressed: () => fleet.disconnectAll(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _StrikeButton(engine: engine),
          const SizedBox(height: 16),
          _StormCard(engine: engine, rain: context.watch<RainPlayer>()),
          const SizedBox(height: 16),
          _ReportCard(engine: engine, connection: connection),
        ],
      ),
    );
  }

}

/// The only control this app really needs.
///
/// Every strike picks its own stretch of strip and its own distance, so there
/// is nothing to set up before pressing it.
class _StrikeButton extends StatelessWidget {
  const _StrikeButton({required this.engine});

  final ThunderEngine engine;

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<Sp621eFleet>();
    final enabled = fleet.isConnected && !engine.isStriking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 96,
          child: FilledButton.icon(
            onPressed: enabled ? () => engine.autoStrike() : null,
            icon: const Icon(Icons.bolt, size: 32),
            label: Text(
              engine.isStriking ? 'Striking…' : 'Strike',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A random ${engine.minSegmentLeds}-${engine.maxSegmentLeds} LED '
          'stretch flares in time with the thunder, then falls back to the '
          'glow.'
          '${fleet.connectedCount > 1 ? ' Both strips strike together.' : ''}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// The cool end of the spectrum, where a storm sky sits. Warm options are
/// deliberately absent: a warm glow leaves a white strike nowhere to jump to.
class _GlowSwatch {
  const _GlowSwatch(this.name, this.r, this.g, this.b);
  final String name;
  final int r;
  final int g;
  final int b;
}

const List<_GlowSwatch> _glowSwatches = [
  _GlowSwatch('Storm', 24, 48, 96),
  _GlowSwatch('Indigo', 40, 40, 110),
  _GlowSwatch('Slate', 60, 70, 90),
  _GlowSwatch('Cyan', 0, 140, 170),
];

class _StormCard extends StatelessWidget {
  const _StormCard({required this.engine, required this.rain});

  final ThunderEngine engine;
  final RainPlayer rain;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Storm mode'),
              subtitle: Text(
                'Fires a random preset every '
                '${engine.stormMinSeconds}-${engine.stormMaxSeconds}s',
              ),
              value: engine.stormMode,
              onChanged: engine.setStormMode,
            ),
            const SizedBox(height: 4),
            const Text('Weather between strikes'),
            const SizedBox(height: 8),
            SegmentedButton<Ambience>(
              segments: [
                for (final a in Ambience.values)
                  ButtonSegment(value: a, label: Text(a.label)),
              ],
              selected: {engine.ambience},
              onSelectionChanged: (s) => engine.setAmbience(s.first),
            ),
            if (engine.ambience != Ambience.off) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Glow'),
                  Expanded(
                    child: Slider(
                      value: engine.glowBrightness.toDouble(),
                      min: 1,
                      max: 160,
                      onChanged: (v) => engine.glowBrightness = v.round(),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${engine.glowBrightness}',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final swatch in _glowSwatches)
                    ChoiceChip(
                      label: Text(swatch.name),
                      selected: engine.glowColor ==
                          (swatch.r, swatch.g, swatch.b),
                      onSelected: (_) =>
                          engine.setGlowColor(swatch.r, swatch.g, swatch.b),
                    ),
                ],
              ),
            ],
            if (engine.ambience == Ambience.rain && rain.failed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No rain sample found. Drop a looping recording at '
                  'assets/audio/rain.mp3 and rebuild. The glow still runs.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
            if (engine.isStriking)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    const Text('Striking…'),
                    const Spacer(),
                    TextButton(
                      onPressed: () => engine.cancel(),
                      child: const Text('Stop'),
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

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.engine, required this.connection});

  final ThunderEngine engine;
  final Sp621eConnection connection;

  @override
  Widget build(BuildContext context) {
    final report = engine.lastReport;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last strike', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (report == null)
              Text(
                'Nothing fired yet.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else ...[
              Row(
                children: [
                  Icon(
                    report.keptTime ? Icons.check_circle : Icons.warning_amber,
                    size: 18,
                    color: report.keptTime ? scheme.primary : scheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(report.presetName)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${report.executed}/${report.planned} steps · '
                '${report.dropped} dropped · '
                'worst ${report.worstLateMs} ms late · '
                '${report.wallClock.inMilliseconds} ms total',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${connection.writesSent} writes sent, '
                '${connection.writesSkipped} skipped as redundant',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              if (!report.keptTime) ...[
                const SizedBox(height: 8),
                Text(
                  'Steps were dropped to stay in time with the sound. Widen the '
                  'gaps by lowering sharpness, or accept a coarser strike.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
