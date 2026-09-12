import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../sp621e/sp621e_connection.dart';
import '../theme.dart';

/// Shows every byte in and out of the controller.
///
/// Worth having on the phone rather than only in a debug console: the protocol
/// is unverified against any given unit until you have watched it answer.
void showLogSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _LogSheet(),
  );
}

class _LogSheet extends StatelessWidget {
  const _LogSheet();

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<Sp621eConnection>();
    final entries = connection.log.reversed.toList();
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('BLE log', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  connection.status == null
                      ? 'no status yet'
                      : 'effect 0x${connection.status!.effect.toRadixString(16)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Ask the controller for its state',
                  icon: const Icon(Icons.download),
                  onPressed: () => connection.requestState(),
                ),
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear_all),
                  onPressed: () => connection.clearLog(),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'Nothing logged yet.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          entry.text,
                          style: kMonoStyle.copyWith(
                            fontSize: 12,
                            color: entry.outbound
                                ? scheme.onSurface
                                : scheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
