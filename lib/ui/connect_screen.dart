import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../ble/storm_service.dart';
import 'widgets/log_panel.dart';
import 'widgets/status_bar.dart';

/// First screen: get permissions, find the light, connect.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  bool _logExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = context.watch<StormService>();
    final denied = service.state == LinkState.permissionDenied;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const StatusBar(showDeviceId: false),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.flash_on,
                          size: 72,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'StromSync',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'ESP32-S3 storm light over Bluetooth LE',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 36),
                        SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: service.isBusy
                                ? null
                                : () => service.scanAndConnect(),
                            icon: service.isBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.bluetooth_searching),
                            label: Text(
                              service.isBusy
                                  ? 'Searching...'
                                  : 'Scan and connect',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (denied) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: openAppSettings,
                            icon: const Icon(Icons.settings_outlined),
                            label: const Text('Open app settings'),
                          ),
                        ],
                        const SizedBox(height: 28),
                        const _Checklist(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            LogPanel(
              expanded: _logExpanded,
              onToggle: () => setState(() => _logExpanded = !_logExpanded),
            ),
          ],
        ),
      ),
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Before you connect', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            const _Bullet('The light is powered and advertising as '
                '"${StormService.deviceName}".'),
            const _Bullet('Phone Bluetooth is on.'),
            const _Bullet(
              'Your Bluetooth speaker is paired in Android settings. '
              'This app never connects to it directly; the OS routes '
              'audio there.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 10),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
