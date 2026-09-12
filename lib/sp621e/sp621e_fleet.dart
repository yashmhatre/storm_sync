import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../led_device.dart';
import 'sp621e_connection.dart';

/// Drives one or more controllers as a single light.
///
/// Two SP621Es are two independent BLE links, which is what makes syncing them
/// possible at all: their writes do not queue behind each other, so the same
/// command can be issued to both at the same moment and land on each within a
/// connection interval or so. Every command here therefore fans out in
/// parallel and waits for all of them, rather than walking the list.
///
/// Nothing above this layer knows how many controllers there are. The strike
/// engine drives a fleet exactly as it drove a single connection.
class Sp621eFleet extends ChangeNotifier {
  final List<LedDevice> _members = [];

  List<LedDevice> get members => List.unmodifiable(_members);

  /// The connection used for scanning and for anything that only makes sense
  /// against one device. The first one added is the one the connect screen
  /// drives.
  Sp621eConnection get primary {
    for (final member in _members) {
      if (member is Sp621eConnection) return member;
    }
    final first = Sp621eConnection();
    _attach(first);
    _members.insert(0, first);
    return first;
  }

  List<LedDevice> get connected =>
      _members.where((m) => m.isConnected).toList();

  /// The connected controllers that can light part of their strip.
  List<LedDevice> get segmentCapable =>
      connected.where((m) => m.supportsSegments).toList();

  bool get hasSegmentCapable => segmentCapable.isNotEmpty;

  int get connectedCount => connected.length;

  bool get isConnected => connected.isNotEmpty;

  /// Adds an idle connection of the right kind for [device].
  LedDevice addSlotFor(LedDevice device) {
    _attach(device);
    _members.add(device);
    notifyListeners();
    return device;
  }

  void _attach(LedDevice device) {
    device.addListener(notifyListeners);
  }

  Future<void> removeSlot(LedDevice connection) async {
    if (_members.length <= 1) {
      // The fleet always keeps one slot, otherwise there is nothing to scan
      // with. Disconnecting is enough.
      await connection.disconnect();
      notifyListeners();
      return;
    }

    _members.remove(connection);
    connection.removeListener(notifyListeners);
    await connection.disconnect();
    connection.dispose();
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Fanned-out commands
  // -------------------------------------------------------------------

  Future<void> _all(Future<void> Function(LedDevice) action) async {
    final targets = connected;
    if (targets.isEmpty) return;
    // Issued together, not one after another: that simultaneity is the whole
    // point of holding separate links.
    await Future.wait(targets.map(action));
  }

  Future<void> setPower(bool on) => _all((c) => c.setPower(on));

  Future<void> setBrightness(int level) =>
      _all((c) => c.setBrightness(level));

  Future<void> setColor(int r, int g, int b, {int? level}) =>
      _all((c) => c.setColor(r, g, b, level: level));

  /// Lights a travelling block, on the controllers that can.
  ///
  /// A plain RGB controller is skipped rather than approximated: it stays in
  /// step through the brightness and colour commands that follow, which is the
  /// most it can honour.
  Future<void> setSegment({
    required int effect,
    required int speed,
    required int length,
    required int brightness,
  }) async {
    final targets = segmentCapable;
    if (targets.isEmpty) return;

    await Future.wait(targets.map((c) => c.setSegment(
          effect: effect,
          speed: speed,
          length: length,
          brightness: brightness,
        )));
  }

  Future<void> setChipOrder(int order) async {
    await Future.wait(
      connected.whereType<Sp621eConnection>().map((c) => c.setChipOrder(order)),
    );
  }

  Future<void> requestState() async {
    await Future.wait(
      connected.whereType<Sp621eConnection>().map((c) => c.requestState()),
    );
  }

  Future<void> flush() => _all((c) => c.flush());

  void invalidateShadow() {
    for (final member in _members) {
      member.invalidateShadow();
    }
  }

  void resetWriteStats() {
    for (final member in _members) {
      member.resetWriteStats();
    }
  }

  int get writesSent =>
      _members.fold(0, (sum, m) => sum + m.writesSent);

  int get writesSkipped =>
      _members.fold(0, (sum, m) => sum + m.writesSkipped);

  /// The slowest link in the fleet.
  ///
  /// A strike is only as quick as its slowest controller, so planning against
  /// the worst case is what keeps two strips striking together instead of one
  /// running ahead.
  int get measuredWriteMs {
    final live = connected;
    if (live.isEmpty) return 40;
    return live.map((c) => c.measuredWriteMs).reduce(max);
  }

  int get chipOrder {
    for (final member in connected) {
      if (member is Sp621eConnection) return member.chipOrder;
    }
    return 0;
  }

  Future<void> disconnectAll() async {
    await Future.wait(_members.map((m) => m.disconnect()));
    notifyListeners();
  }

  /// Connects [connection] to [device], then brings it in line with whatever
  /// the rest of the fleet is already showing.
  Future<void> connect(
    LedDevice connection,
    BluetoothDevice device,
  ) async {
    await connection.connect(device);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final member in _members) {
      member.removeListener(notifyListeners);
      member.dispose();
    }
    _members.clear();
    super.dispose();
  }
}
