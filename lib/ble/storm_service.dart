import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../model/params.dart';
import 'command_log.dart';
import 'write_throttle.dart';

/// Where the link is in its lifecycle. Drives the status line everywhere.
enum LinkState {
  /// Nothing attempted yet, or deliberately disconnected.
  idle,

  /// Runtime permissions have been refused.
  permissionDenied,

  /// The phone's Bluetooth radio is off or unavailable.
  adapterOff,

  scanning,
  connecting,

  /// Connected at the GATT level, still enumerating services.
  discovering,

  /// Fully usable: RX write and TX notify are both live.
  ready,

  /// Lost the link and waiting for the device to come back.
  reconnecting,

  /// Gave up. The user has to press Connect again.
  failed,
}

/// Owns the one BLE connection to the storm light and everything derived from
/// it: the parsed parameter map, the command log and the write throttle.
///
/// Nothing in here touches widgets. Screens listen and call [send],
/// [setParameter] and friends; all BLE work happens off the build path.
class StormService extends ChangeNotifier {
  StormService();

  // ---------------------------------------------------------------- constants

  /// The name the firmware advertises. Note the spelling: it is "StromSync".
  static const String deviceName = 'StromSync';

  /// Nordic UART Service.
  static final Guid nusService = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');

  /// Phone to device. Commands are written here.
  static final Guid nusRxCharacteristic =
      Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');

  /// Device to phone. Replies arrive here as notifications.
  static final Guid nusTxCharacteristic =
      Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');

  /// A slider drag fires far faster than a BLE connection interval. One write
  /// per key per 100 ms keeps the link responsive; the final value always
  /// lands because [setParameter] is called again with `finalValue: true`.
  static const Duration throttleInterval = Duration(milliseconds: 100);

  /// Notification payloads are reassembled into lines. If a fragment sits in
  /// the buffer with no newline for this long, treat it as a whole line, so
  /// firmware that omits a trailing newline still gets parsed.
  static const Duration _lineFlushDelay = Duration(milliseconds: 60);

  static const Duration _scanTimeout = Duration(seconds: 12);
  static const int _maxLogEntries = 500;

  /// Throttle bucket names for the commands that are not `SET <key>`.
  static const String _colorBucket = 'COLOR';
  static const String _tintBucket = 'TINT';

  // -------------------------------------------------------------------- state

  LinkState _state = LinkState.idle;
  LinkState get state => _state;

  String _status = 'Not connected';

  /// One-line, human-readable connection status for the UI.
  String get status => _status;

  bool get isConnected => _state == LinkState.ready;

  /// True once we have picked a device and still intend to be talking to it.
  ///
  /// This is what decides whether the app shows the controls or the connect
  /// screen. It deliberately stays true across a dropped link, so a brief
  /// dropout leaves the user on the controls watching the reconnect rather
  /// than being thrown back to the start.
  bool get hasSession => _wantConnection && _device != null;

  /// True while a connect attempt or reconnect is in flight.
  bool get isBusy =>
      _state == LinkState.scanning ||
      _state == LinkState.connecting ||
      _state == LinkState.discovering ||
      _state == LinkState.reconnecting;

  final Map<String, int> _parameters = {};

  /// Last known device state, keyed by wire name. Populated by `LIST` and kept
  /// current by every `key=value` line the device sends.
  Map<String, int> get parameters => UnmodifiableMapView(_parameters);

  final List<LogEntry> _log = [];
  List<LogEntry> get log => UnmodifiableListView(_log);

  BluetoothDevice? _device;
  BluetoothDevice? get device => _device;

  /// Remote id of the device we are talking to, shown in the UI.
  String? get deviceId => _device?.remoteId.str;

  String? _mode;

  /// Last mode we asked the light for, or null if unknown. Used only to show
  /// which of the three mode buttons is active.
  String? get mode => _mode;

  BluetoothCharacteristic? _rxCharacteristic;

  /// Some firmware exposes RX as write-with-response only. We prefer
  /// write-without-response but fall back rather than failing every write.
  bool _rxSupportsWriteWithoutResponse = true;

  /// Set while the user wants a link. Distinguishes "the device dropped out"
  /// (reconnect) from "the user pressed Disconnect" (stay down).
  bool _wantConnection = false;

  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;

  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  /// Serialises writes. Overlapping GATT writes on one device are not safe;
  /// chaining them also keeps command order intact.
  Future<void> _writeChain = Future<void>.value();

  late final WriteThrottle _throttle = WriteThrottle(
    interval: throttleInterval,
    onSend: _enqueueWrite,
  );

  final StringBuffer _rxBuffer = StringBuffer();
  Timer? _rxFlushTimer;

  bool _disposed = false;

  // --------------------------------------------------------------- public API

  /// Must be called once before scanning. Safe to call repeatedly.
  Future<void> start() async {
    _adapterSub ??= FlutterBluePlus.adapterState.listen(_onAdapterState);
  }

  /// Asks for the runtime permissions BLE needs on this OS version.
  ///
  /// Android 12+ needs BLUETOOTH_SCAN and BLUETOOTH_CONNECT. Older Android
  /// refuses to return scan results without a location grant. On iOS the
  /// permission is implicit in the first CoreBluetooth call, so this is a
  /// no-op there and returns true.
  Future<bool> requestPermissions() async {
    if (!_isAndroid) return true;

    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scan = results[Permission.bluetoothScan];
    final connect = results[Permission.bluetoothConnect];
    final location = results[Permission.locationWhenInUse];

    // On Android 12+ the two Bluetooth grants are what matter and location is
    // not required. On Android 11 and below the Bluetooth grants auto-resolve
    // and location is the load-bearing one. Accepting either shape covers both.
    final granted =
        ((scan?.isGranted ?? false) && (connect?.isGranted ?? false)) ||
            (location?.isGranted ?? false);

    if (!granted) {
      _setState(LinkState.permissionDenied, 'Bluetooth permission denied');
      _addLog(
        LogKind.error,
        'Permissions refused: scan=$scan connect=$connect location=$location',
      );
    }
    return granted;
  }

  /// Scans for [deviceName] and connects to the first match.
  Future<void> scanAndConnect() async {
    if (isBusy) return;

    await start();
    _wantConnection = true;
    // Drop any device from a previous session so a failed scan falls back to
    // the connect screen rather than resurrecting a stale handle.
    _device = null;

    if (!await requestPermissions()) return;

    if (!await FlutterBluePlus.isSupported) {
      _setState(LinkState.failed, 'This device has no Bluetooth LE support');
      return;
    }

    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      _setState(LinkState.adapterOff, 'Turn Bluetooth on to continue');
      if (!_isAndroid) return;
      try {
        // Android can prompt to enable the radio. If the user declines, the
        // adapter listener keeps the status honest.
        await FlutterBluePlus.turnOn();
      } catch (e) {
        _addLog(LogKind.error, 'Could not turn Bluetooth on: $e');
        return;
      }
    }

    _setState(LinkState.scanning, 'Scanning for $deviceName...');
    _addLog(LogKind.info, 'Scan started, looking for "$deviceName"');

    // Resolves to the first matching device, or to null when the scan window
    // closes empty.
    //
    // The scan-finished signal has to come from `isScanning`, not from the
    // results stream: flutter_blue_plus never closes `onScanResults`, so
    // awaiting it directly would hang forever when the light is switched off.
    final completer = Completer<ScanResult?>();
    StreamSubscription<List<ScanResult>>? resultsSub;
    StreamSubscription<bool>? scanningSub;

    // Devices already named in the log, so a 12-second scan does not write the
    // same advertisement a hundred times.
    final seen = <String>{};

    ScanResult? found;
    try {
      // Subscribe before starting so no advertisement is missed in the gap.
      resultsSub = FlutterBluePlus.onScanResults.listen(
        (results) {
          for (final result in results) {
            final id = result.device.remoteId.str;
            if (seen.add(id)) {
              final name = _nameOf(result);
              _addLog(
                LogKind.info,
                'Saw ${name.isEmpty ? '(unnamed)' : name} '
                '[$id] at ${result.rssi} dBm',
              );
            }
          }

          if (completer.isCompleted) return;
          for (final result in results) {
            if (_matchesDeviceName(result)) {
              completer.complete(result);
              return;
            }
          }
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
      );

      // Deliberately unfiltered. Android's native name filter matches only the
      // complete local name, so firmware that advertises a shortened name goes
      // missing with no way to tell that apart from a light that is switched
      // off. Scanning wide and matching here means the log names every device
      // in range, which is what you actually need during bring-up.
      await FlutterBluePlus.startScan(timeout: _scanTimeout);

      // Subscribed after startScan, so the first value this behaviour stream
      // replays is `true`. The `false` that follows is the timeout firing.
      scanningSub = FlutterBluePlus.isScanning.listen((scanning) {
        if (scanning || completer.isCompleted) return;
        completer.complete(null);
      });

      found = await completer.future;
    } catch (e) {
      _setState(LinkState.failed, 'Scan failed: $e');
      _addLog(LogKind.error, 'Scan failed: $e');
      return;
    } finally {
      await resultsSub?.cancel();
      await scanningSub?.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {
        // Already stopped by the timeout; nothing to do.
      }
    }

    final match = found;
    if (match == null) {
      _setState(LinkState.failed, 'No "$deviceName" found. Is it powered on?');
      _addLog(LogKind.error, 'Scan finished with no match');
      return;
    }

    _addLog(
      LogKind.info,
      'Found ${match.device.remoteId.str} at ${match.rssi} dBm',
    );
    await connectTo(match.device);
  }

  /// Connects to an already-known device.
  Future<void> connectTo(BluetoothDevice target) async {
    _wantConnection = true;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();

    _device = target;
    _setState(LinkState.connecting, 'Connecting to ${target.remoteId.str}...');

    await _connectionSub?.cancel();
    _connectionSub = target.connectionState.listen(_onConnectionState);

    try {
      // License.nonprofit is the flutter_blue_plus 2.x declaration for personal
      // and non-commercial use. See the licence note in README.md.
      await target.connect(license: License.nonprofit);
    } catch (e) {
      _addLog(LogKind.error, 'Connect failed: $e');
      if (_wantConnection) {
        _scheduleReconnect();
      } else {
        _setState(LinkState.failed, 'Connect failed: $e');
      }
    }
  }

  /// Tears the link down and stops auto-reconnect.
  Future<void> disconnect() async {
    _wantConnection = false;
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    _cancelThrottles();

    final target = _device;
    _rxCharacteristic = null;
    _mode = null;

    await _notifySub?.cancel();
    _notifySub = null;

    if (target != null) {
      try {
        await target.disconnect();
      } catch (e) {
        _addLog(LogKind.error, 'Disconnect failed: $e');
      }
    }

    await _connectionSub?.cancel();
    _connectionSub = null;

    _setState(LinkState.idle, 'Not connected');
    _addLog(LogKind.info, 'Disconnected by user');
  }

  /// Queues a raw command. Returns immediately; the write happens in order on
  /// the write chain. Use this for one-shot commands like `STRIKE 200`.
  void send(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return;
    _enqueueWrite(trimmed);
  }

  /// Re-reads every parameter from the device.
  void refreshParameters() => send('LIST');

  /// `MODE OFF` | `MODE GLOW` | `MODE STORM`.
  ///
  /// The firmware does not announce its mode, so [mode] tracks what we last
  /// asked for. It is cleared on disconnect rather than being trusted across
  /// a link drop.
  void setMode(String next) {
    final upper = next.toUpperCase();
    _mode = upper;
    send('MODE $upper');
    _notify();
  }

  /// Throttled `SET <key> <value>`.
  ///
  /// Call with [finalValue] false from `onChanged` and true from
  /// `onChangeEnd`, so a drag costs at most ten writes per second per key but
  /// the value the finger stopped on is always delivered.
  void setParameter(String key, int value, {bool finalValue = false}) {
    final spec = kParamsByKey[key];
    final clamped = spec?.clampValue(value) ?? value;

    // Optimistic local update, so that when the slider releases its own drag
    // value the map already holds the new number instead of snapping back to
    // whatever the device last reported.
    final changed = _parameters[key] != clamped;
    _parameters[key] = clamped;

    // Only notify on release. A drag calls this ~60 times a second and the
    // slider renders its own in-flight value, so notifying here would rebuild
    // the whole tuning tab at drag rate for no visible gain.
    if (changed && finalValue) _notify();

    _throttledWrite(key, 'SET $key $clamped', finalValue: finalValue);
  }

  /// Throttled `COLOR <r> <g> <b>`, the bolt colour.
  void setColor(int r, int g, int b, {bool finalValue = false}) {
    _throttledWrite(
      _colorBucket,
      'COLOR ${_byte(r)} ${_byte(g)} ${_byte(b)}',
      finalValue: finalValue,
    );
  }

  /// Throttled `TINT <r> <g> <b>`, the cloud colour.
  void setTint(int r, int g, int b, {bool finalValue = false}) {
    _throttledWrite(
      _tintBucket,
      'TINT ${_byte(r)} ${_byte(g)} ${_byte(b)}',
      finalValue: finalValue,
    );
  }

  void clearLog() {
    _log.clear();
    _notify();
  }

  /// The whole log as text, for the copy button.
  String logAsText() => _log.map((e) => e.toString()).join('\n');

  // ------------------------------------------------------ connection plumbing

  void _onAdapterState(BluetoothAdapterState adapterState) {
    if (adapterState == BluetoothAdapterState.on) {
      if (_state == LinkState.adapterOff) {
        _setState(LinkState.idle, 'Bluetooth on. Ready to scan.');
      }
      return;
    }
    if (adapterState == BluetoothAdapterState.off ||
        adapterState == BluetoothAdapterState.turningOff) {
      _rxCharacteristic = null;
      _setState(LinkState.adapterOff, 'Bluetooth is off');
      _addLog(LogKind.error, 'Adapter went to $adapterState');
    }
  }

  void _onConnectionState(BluetoothConnectionState connectionState) {
    if (connectionState == BluetoothConnectionState.connected) {
      _addLog(LogKind.info, 'GATT connected');
      _reconnectAttempt = 0;
      unawaited(_onConnected());
      return;
    }

    // Disconnected. The light may reboot into its own default mode, so what
    // we last asked for is no longer something we can claim to know.
    _rxCharacteristic = null;
    _mode = null;
    _notifySub?.cancel();
    _notifySub = null;
    _cancelThrottles();

    if (_wantConnection) {
      _addLog(LogKind.error, 'Link dropped');
      _scheduleReconnect();
    } else {
      _setState(LinkState.idle, 'Not connected');
    }
  }

  Future<void> _onConnected() async {
    final target = _device;
    if (target == null) return;

    _setState(LinkState.discovering, 'Discovering services...');

    try {
      // Services must be rediscovered after every reconnect; the list cached
      // from the previous session is not valid for a new GATT connection.
      final services = await target.discoverServices();

      BluetoothService? uart;
      for (final service in services) {
        if (service.serviceUuid == nusService) {
          uart = service;
          break;
        }
      }

      if (uart == null) {
        _addLog(
          LogKind.error,
          'Missing ${nusService.str}. Saw: '
          '${services.map((s) => s.serviceUuid.str).join(', ')}',
        );
        _wantConnection = false;
        _setState(LinkState.failed, 'Nordic UART service not found');
        await target.disconnect();
        return;
      }

      BluetoothCharacteristic? pick(Guid id) {
        for (final characteristic in uart!.characteristics) {
          if (characteristic.characteristicUuid == id) return characteristic;
        }
        return null;
      }

      final rx = pick(nusRxCharacteristic);
      final tx = pick(nusTxCharacteristic);

      if (rx == null || tx == null) {
        _addLog(
          LogKind.error,
          'RX found: ${rx != null}, TX found: ${tx != null}',
        );
        _wantConnection = false;
        _setState(LinkState.failed, 'UART characteristics missing');
        await target.disconnect();
        return;
      }

      _rxCharacteristic = rx;
      _rxSupportsWriteWithoutResponse = rx.properties.writeWithoutResponse;
      if (!_rxSupportsWriteWithoutResponse) {
        _addLog(
          LogKind.info,
          'RX has no write-without-response; falling back to acked writes',
        );
      }

      await _notifySub?.cancel();
      final sub = tx.onValueReceived.listen(_onNotification);
      _notifySub = sub;
      target.cancelWhenDisconnected(sub);
      await tx.setNotifyValue(true);
      _addLog(LogKind.info, 'TX notifications enabled');

      _setState(LinkState.ready, 'Connected to $deviceName');

      // Pull the full device state so every slider starts where the hardware
      // actually is, not at some app-side default.
      refreshParameters();
    } catch (e) {
      _addLog(LogKind.error, 'Service discovery failed: $e');
      if (_wantConnection) {
        _scheduleReconnect();
      } else {
        _setState(LinkState.failed, 'Service discovery failed: $e');
      }
    }
  }

  void _scheduleReconnect() {
    if (_disposed || !_wantConnection) return;
    _reconnectTimer?.cancel();

    _reconnectAttempt++;
    // 1s, 2s, 4s, 8s, then hold at 10s. Fast enough to feel automatic, slow
    // enough not to hammer the radio while the light is unplugged.
    final seconds = switch (_reconnectAttempt) {
      1 => 1,
      2 => 2,
      3 => 4,
      4 => 8,
      _ => 10,
    };

    _setState(
      LinkState.reconnecting,
      'Reconnecting in ${seconds}s (attempt $_reconnectAttempt)...',
    );

    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      if (_disposed || !_wantConnection) return;
      final target = _device;
      if (target == null) return;

      _setState(LinkState.reconnecting, 'Reconnecting...');
      try {
        await target.connect(license: License.nonprofit);
      } catch (e) {
        _addLog(LogKind.error, 'Reconnect attempt failed: $e');
        _scheduleReconnect();
      }
    });
  }

  // ------------------------------------------------------------------ writing

  void _throttledWrite(
    String bucket,
    String command, {
    required bool finalValue,
  }) {
    _throttle.submit(bucket, command, isFinal: finalValue);
  }

  void _cancelThrottles() => _throttle.cancelAll();

  void _enqueueWrite(String command) {
    _writeChain = _writeChain.then((_) => _write(command));
  }

  Future<void> _write(String command) async {
    final characteristic = _rxCharacteristic;
    if (characteristic == null) {
      _addLog(LogKind.error, 'Dropped "$command": not connected');
      return;
    }

    try {
      // One command per write, no terminator: the firmware treats each GATT
      // write as a complete command.
      await characteristic.write(
        utf8.encode(command),
        withoutResponse: _rxSupportsWriteWithoutResponse,
      );
      _addLog(LogKind.sent, command);
    } catch (e) {
      _addLog(LogKind.error, 'Write "$command" failed: $e');
    }
  }

  // ------------------------------------------------------------------ reading

  void _onNotification(List<int> data) {
    if (data.isEmpty) return;
    _rxBuffer.write(utf8.decode(data, allowMalformed: true));
    _rxFlushTimer?.cancel();

    final parts = _rxBuffer.toString().split(RegExp(r'\r\n|\r|\n'));
    // Everything before the last element is a complete line. The tail may be a
    // partial line still arriving, so it stays buffered.
    final tail = parts.removeLast();
    for (final line in parts) {
      _handleLine(line);
    }

    _rxBuffer
      ..clear()
      ..write(tail);

    if (tail.isNotEmpty) {
      _rxFlushTimer = Timer(_lineFlushDelay, () {
        final remainder = _rxBuffer.toString();
        _rxBuffer.clear();
        if (remainder.trim().isNotEmpty) _handleLine(remainder);
      });
    }
  }

  /// Matches `key=value` anywhere in a line, so a bare `bri=128`, an
  /// `OK bri=128` and a multi-pair `LIST` line are all picked up.
  static final RegExp _kvPattern =
      RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(-?\d+)');

  void _handleLine(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return;

    final isError = line.toUpperCase().startsWith('ERR');
    _addLog(isError ? LogKind.error : LogKind.received, line, notify: false);

    for (final match in _kvPattern.allMatches(line)) {
      final key = match.group(1)!;
      final value = int.tryParse(match.group(2)!);
      if (value != null) _parameters[key] = value;
    }

    _notify();
  }

  // ------------------------------------------------------------------ helpers

  static int _byte(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

  /// Best available name for a scan hit.
  ///
  /// `advName` is what this advertisement carried; `platformName` is what the
  /// OS has cached, which is populated for bonded devices whose current
  /// advertisement omits the name.
  static String _nameOf(ScanResult result) {
    final advertised = result.advertisementData.advName.trim();
    if (advertised.isNotEmpty) return advertised;
    return result.device.platformName.trim();
  }

  /// Case-insensitive match against [deviceName], checking both names a device
  /// can present.
  static bool _matchesDeviceName(ScanResult result) {
    final target = deviceName.toLowerCase();
    return result.advertisementData.advName.trim().toLowerCase() == target ||
        result.device.platformName.trim().toLowerCase() == target;
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _setState(LinkState next, String message) {
    _state = next;
    _status = message;
    _notify();
  }

  void _addLog(LogKind kind, String text, {bool notify = true}) {
    _log.add(LogEntry(kind, text));
    if (_log.length > _maxLogEntries) {
      _log.removeRange(0, _log.length - _maxLogEntries);
    }
    if (kDebugMode) debugPrint('[StromSync] ${_log.last}');
    if (notify) _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _wantConnection = false;
    _reconnectTimer?.cancel();
    _rxFlushTimer?.cancel();
    _cancelThrottles();
    _connectionSub?.cancel();
    _notifySub?.cancel();
    _adapterSub?.cancel();
    unawaited(_device?.disconnect().catchError((_) {}));
    super.dispose();
  }
}
