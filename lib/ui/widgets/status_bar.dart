import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ble/storm_service.dart';

/// One-line connection status. Deliberately always on screen: when a command
/// does nothing, the first question is whether the link is up.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, this.showDeviceId = true});

  final bool showDeviceId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = context.watch<StormService>();
    final tone = _toneFor(service.state, theme.colorScheme);

    return Container(
      width: double.infinity,
      color: tone.background,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: service.isBusy
                ? CircularProgressIndicator(strokeWidth: 2, color: tone.foreground)
                : Icon(tone.icon, size: 14, color: tone.foreground),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              service.status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: tone.foreground,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (showDeviceId && service.deviceId != null)
            Text(
              service.deviceId!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tone.foreground.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tone {
  const _Tone(this.background, this.foreground, this.icon);
  final Color background;
  final Color foreground;
  final IconData icon;
}

_Tone _toneFor(LinkState state, ColorScheme scheme) => switch (state) {
      LinkState.ready => const _Tone(
          Color(0xFF15321F),
          Color(0xFF8FE6A6),
          Icons.bluetooth_connected,
        ),
      LinkState.reconnecting || LinkState.adapterOff => const _Tone(
          Color(0xFF3A2E12),
          Color(0xFFF2CE7A),
          Icons.bluetooth_searching,
        ),
      LinkState.failed || LinkState.permissionDenied => const _Tone(
          Color(0xFF3B1B1B),
          Color(0xFFFF9D8A),
          Icons.error_outline,
        ),
      LinkState.scanning ||
      LinkState.connecting ||
      LinkState.discovering =>
        _Tone(
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
          Icons.bluetooth_searching,
        ),
      LinkState.idle => _Tone(
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
          Icons.bluetooth_disabled,
        ),
    };
