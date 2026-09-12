import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../sp621e/sp621e_connection.dart';
import '../../thunder/bolt_segments.dart';
import '../../thunder/strip_calibration.dart';
import '../../thunder/thunder_engine.dart';
import 'strip_preview.dart';

/// Defines where each physical bolt shape sits along the strip.
///
/// The strip is one continuous run bent into separate zigzags with plain
/// connecting runs between them, and only the zigzags are worth lighting. This
/// screen is how the app learns which LED ranges those are.
///
/// Nothing about this can be measured automatically: the controller does not
/// report anything, so the ranges are found by eye. **Show me** lights the
/// block where a bolt is currently defined, so you can nudge the numbers until
/// the right shape lights up.
class BoltsScreen extends StatelessWidget {
  const BoltsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bolts = context.watch<BoltSegmentStore>();
    final calibration = context.watch<StripCalibrationStore>().value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bolts'),
        actions: [
          IconButton(
            tooltip: 'Add a bolt',
            icon: const Icon(Icons.add),
            onPressed: () => bolts.add(pixelCount: calibration.pixelCount),
          ),
          IconButton(
            tooltip: 'Reset to evenly spaced',
            icon: const Icon(Icons.restart_alt),
            onPressed: () =>
                bolts.restoreDefaults(pixelCount: calibration.pixelCount),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Your strip is bent into separate bolt shapes with connecting runs '
            'between them. Tell the app which LEDs each shape covers and a '
            'strike can light one bolt instead of a stretch of strip.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Calibrate the strip first, otherwise the timing that puts light on '
            'a bolt will be wrong however accurate these numbers are.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          for (final bolt in bolts.segments) ...[
            _BoltCard(bolt: bolt, calibration: calibration),
            const SizedBox(height: 12),
          ],
          if (bolts.segments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No bolts defined yet.')),
            ),
        ],
      ),
    );
  }
}

class _BoltCard extends StatelessWidget {
  const _BoltCard({required this.bolt, required this.calibration});

  final BoltSegment bolt;
  final StripCalibration calibration;

  @override
  Widget build(BuildContext context) {
    final store = context.read<BoltSegmentStore>();
    final engine = context.watch<ThunderEngine>();
    final connection = context.watch<Sp621eConnection>();
    final pixelCount = calibration.pixelCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    bolt.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => store.remove(bolt.id),
                ),
              ],
            ),
            Text(
              'LEDs ${bolt.startPixel}–${bolt.endPixel} · '
              '${bolt.length} long',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            StripPreview(
              position: bolt.positionIn(calibration),
              widthPixels: bolt.length,
              pixelCount: pixelCount,
            ),
            const SizedBox(height: 10),
            _PixelRow(
              label: 'Start',
              value: bolt.startPixel,
              max: pixelCount,
              onChanged: (v) => store.upsert(bolt.copyWith(startPixel: v)),
            ),
            _PixelRow(
              label: 'End',
              value: bolt.endPixel,
              max: pixelCount,
              onChanged: (v) => store.upsert(bolt.copyWith(endPixel: v)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: connection.isConnected && !engine.isStriking
                      ? () => _showMe(engine, bolt)
                      : null,
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('Show me'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Lights this bolt and holds it, so the numbers can be checked against the
  /// actual strip rather than guessed.
  void _showMe(ThunderEngine engine, BoltSegment bolt) {
    engine.locateBolt(bolt);
  }
}

class _PixelRow extends StatelessWidget {
  const _PixelRow({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 44, child: Text(label)),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove, size: 18),
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
        ),
        Expanded(
          child: Slider(
            value: value.toDouble().clamp(0, max.toDouble()),
            max: max.toDouble(),
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 18),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
        SizedBox(
          width: 44,
          child: Text('$value', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
