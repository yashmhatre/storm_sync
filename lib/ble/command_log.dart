/// Rolling record of everything that crossed the BLE link, plus the connection
/// narration around it. This is the primary debugging surface for the firmware,
/// so it keeps both directions and never blocks on the UI reading it.
library;

enum LogKind {
  /// Written to the RX characteristic.
  sent,

  /// Arrived on the TX notify characteristic.
  received,

  /// Connection lifecycle narration.
  info,

  /// Something went wrong locally, or the device answered `ERR ...`.
  error,
}

class LogEntry {
  LogEntry(this.kind, this.text) : timestamp = DateTime.now();

  final LogKind kind;
  final String text;
  final DateTime timestamp;

  String get clockText {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(timestamp.hour)}:${two(timestamp.minute)}:'
        '${two(timestamp.second)}.${three(timestamp.millisecond)}';
  }

  String get prefix => switch (kind) {
        LogKind.sent => '>>',
        LogKind.received => '<<',
        LogKind.info => '--',
        LogKind.error => '!!',
      };

  @override
  String toString() => '$clockText $prefix $text';
}
