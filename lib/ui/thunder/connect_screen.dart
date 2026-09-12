import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../sp621e/sp621e_connection.dart';
import '../../led_device.dart';
import '../../melk/melk_connection.dart';
import '../../melk/melk_protocol.dart';
import '../../sp621e/sp621e_fleet.dart';

/// Finds the controller and connects to it.
///
/// Devices that advertise BanlanX's company ID with an SP621E signature are
/// listed first and marked, because the same FFE0/FFE1 pair is used by a lot of
/// unrelated BLE lights and connecting to the wrong one wastes a lot of time.
class ThunderConnectScreen extends StatefulWidget {
  const ThunderConnectScreen({super.key});

  @override
  State<ThunderConnectScreen> createState() => _ThunderConnectScreenState();
}

class _ThunderConnectScreenState extends State<ThunderConnectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<Sp621eConnection>().startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<Sp621eFleet>();
    final connection = fleet.primary;
    final scanning = connection.link == Sp621eLinkState.scanning;
    final connecting = connection.link == Sp621eLinkState.connecting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect'),
        actions: [
          IconButton(
            tooltip: 'Scan again',
            onPressed: scanning || connecting
                ? null
                : () => connection.startScan(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (scanning || connecting) const LinearProgressIndicator(),
          if (fleet.connectedCount > 0)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainer,
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${fleet.connectedCount} controller'
                      '${fleet.connectedCount == 1 ? '' : 's'} linked. '
                      'Tap another to add it, or carry on.',
                    ),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connecting ? 'Connecting…' : 'Looking for your SP621E',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'The controller only accepts one connection at a time. If it '
                  'does not appear, close the LotusLantern app first.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: connection.candidates.isEmpty
                ? _Empty(scanning: scanning)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: connection.candidates.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final candidate = connection.candidates[index];
                      return Card(
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          leading: Icon(
                            candidate.looksLikeSp621e
                                ? Icons.bolt
                                : Icons.bluetooth,
                            color: candidate.looksLikeSp621e
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          title: Text(candidate.name),
                          subtitle: Text(
                            candidate.model != null
                                ? '${candidate.model} · ${candidate.rssi} dBm'
                                : '${candidate.id} · ${candidate.rssi} dBm',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: connecting
                              ? null
                              : () => _connect(fleet, candidate),
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

/// Points the first idle slot at [candidate], adding one if every slot is
/// already driving a controller. This is what lets a second strip join without
/// disturbing the first.
Future<void> _connect(Sp621eFleet fleet, Sp621eCandidate candidate) async {
  final alreadyLinked = fleet.members.any(
    (m) => m.isConnected && m.deviceId == candidate.id,
  );
  if (alreadyLinked) return;

  // Two protocols, two kinds of link. Reuse an idle slot only when it is
  // already the right kind, otherwise a MELK would be handed a BanlanX link
  // and quietly fail to respond.
  final wantsMelk = Melk.looksLikeMelk(candidate.name);

  LedDevice? slot;
  for (final member in fleet.members) {
    if (member.isConnected) continue;
    final isMelk = member is MelkConnection;
    if (isMelk == wantsMelk) {
      slot = member;
      break;
    }
  }

  slot ??= fleet.addSlotFor(
    wantsMelk ? MelkConnection() : Sp621eConnection(),
  );

  await fleet.connect(slot, candidate.device);
}

class _Empty extends StatelessWidget {
  const _Empty({required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          scanning
              ? 'Scanning…'
              : 'Nothing found. Check the controller has power and that '
                  'Bluetooth is on, then scan again.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
