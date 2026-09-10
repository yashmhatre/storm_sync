import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../ble/command_log.dart';
import '../../ble/storm_service.dart';
import '../theme.dart';

/// Collapsible traffic log, docked to the bottom of the screen.
///
/// Collapsed it is a single tappable bar showing the most recent line, so the
/// last thing that happened is always visible without opening anything.
/// Expanded it is a scrolling transcript with copy and clear.
class LogPanel extends StatefulWidget {
  const LogPanel({
    super.key,
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final ScrollController _scroll = ScrollController();
  int _lastLength = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Follows the tail only when the user is already near it, so scrolling back
  /// through history is not yanked away by incoming traffic.
  void _autoScroll(int length) {
    if (length == _lastLength) return;
    _lastLength = length;
    if (!widget.expanded) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.maxScrollExtent - position.pixels > 120) return;
      position.jumpTo(position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = context.watch<StormService>();
    final entries = service.log;
    _autoScroll(entries.length);

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          _Header(
            expanded: widget.expanded,
            onToggle: widget.onToggle,
            entries: entries,
            onCopy: entries.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: service.logAsText()),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${entries.length} log lines copied'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
            onClear: entries.isEmpty ? null : service.clearLog,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: widget.expanded ? 260 : 0,
              width: double.infinity,
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        'Nothing logged yet.',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: entries.length,
                        itemExtent: 18,
                        itemBuilder: (context, index) =>
                            _LogLine(entry: entries[index]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.expanded,
    required this.onToggle,
    required this.entries,
    required this.onCopy,
    required this.onClear,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final List<LogEntry> entries;
  final VoidCallback? onCopy;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = entries.isEmpty ? null : entries.last;

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text('Log', style: theme.textTheme.labelLarge),
            const SizedBox(width: 8),
            Expanded(
              child: latest == null
                  ? Text(
                      'tap to open',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Text(
                      '${latest.prefix} ${latest.text}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kMonoStyle.copyWith(
                        fontSize: 11,
                        color: _colorFor(latest.kind, theme.colorScheme),
                      ),
                    ),
            ),
            if (expanded) ...[
              IconButton(
                tooltip: 'Copy log',
                visualDensity: VisualDensity.compact,
                onPressed: onCopy,
                icon: const Icon(Icons.copy_all, size: 18),
              ),
              IconButton(
                tooltip: 'Clear log',
                visualDensity: VisualDensity.compact,
                onPressed: onClear,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${entries.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${entry.clockText} ',
            style: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ),
          TextSpan(
            text: '${entry.prefix} ',
            style: TextStyle(color: _colorFor(entry.kind, scheme)),
          ),
          TextSpan(
            text: entry.text,
            style: TextStyle(color: _colorFor(entry.kind, scheme)),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: kMonoStyle.copyWith(fontSize: 11, height: 1.5),
    );
  }
}

Color _colorFor(LogKind kind, ColorScheme scheme) => switch (kind) {
      LogKind.sent => const Color(0xFF8CC9FF),
      LogKind.received => const Color(0xFF9BE8A8),
      LogKind.info => scheme.onSurfaceVariant,
      LogKind.error => const Color(0xFFFF9D8A),
    };
