import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ble/storm_service.dart';
import '../../model/params.dart';
import '../theme.dart';
import '../widgets/param_slider.dart';

/// One slider per firmware parameter, plus the persistence commands.
class TuningTab extends StatelessWidget {
  const TuningTab({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<StormService>();
    final enabled = service.isConnected;
    final values = service.parameters;

    // Anything the device reported that we have no slider for. Firmware often
    // grows keys ahead of the app, and seeing them beats guessing.
    final extras = values.keys.where((k) => !kParamsByKey.containsKey(k)).toList()
      ..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _PersistenceRow(enabled: enabled),
        const SizedBox(height: 8),
        for (final group in kParamGroups) ...[
          const SizedBox(height: 14),
          Text(
            group.title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  for (final spec in group.params)
                    ParamSlider(
                      spec: spec,
                      value: values[spec.key],
                      enabled: enabled,
                      onChanged: (value, {required isFinal}) =>
                          service.setParameter(
                        spec.key,
                        value,
                        finalValue: isFinal,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (extras.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(
            'OTHER VALUES REPORTED BY THE DEVICE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final key in extras)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '$key = ${values[key]}',
                        style: kMonoStyle.copyWith(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PersistenceRow extends StatelessWidget {
  const _PersistenceRow({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final service = context.read<StormService>();

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: enabled ? () => service.send('SAVE') : null,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('SAVE'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: enabled
                ? () {
                    service.send('LOAD');
                    // LOAD changes the device state wholesale, so pull the new
                    // values back rather than leaving stale sliders on screen.
                    service.refreshParameters();
                  }
                : null,
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('LOAD'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: enabled ? () => _confirmReset(context, service) : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF9D8A),
            ),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('RESET'),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmReset(
    BuildContext context,
    StormService service,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset the light?'),
        content: const Text(
          'RESET puts every parameter back to the firmware defaults. '
          'Unsaved tuning is lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    service.send('RESET');
    service.refreshParameters();
  }
}
