import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../led_device.dart';
import '../melk/melk_protocol.dart';
import 'banlanx2_protocol.dart';
import 'sp621e_effects.dart';

enum Sp621eLinkState { disconnected, scanning, connecting, connected }

/// One line of the byte-level log, so the link can be debugged on the phone
/// rather than only over a USB cable.
class Sp621eLogEntry {
  Sp621eLogEntry(this.text, {this.outbound = true}) : at = DateTime.now();

  final String text;
  final bool outbound;
  final DateTime at;
}

/// A discovered controller, with enough of the advertisement kept to tell an
/// SP621E apart from the other SPxxxE models that share this protocol.
class Sp621eCandidate {
  const Sp621eCandidate({
    required this.device,
    required this.name,
    required this.rssi,
    required this.looksLikeSp621e,
    this.model,
    this.manufacturerData,
  });

  /// The model name, when the advertisement matches a controller that speaks
  /// this protocol. Null means the frames this app sends may not be understood.
  final String? model;

  /// Raw manufacturer payload, kept so an unrecognised controller can still be
  /// identified from the log rather than guessed at.
  final List<int>? manufacturerData;

  final BluetoothDevice device;
  final String name;
  final int rssi;

  /// True when this is a controller the app knows how to drive, by either
  /// protocol.
  final bool looksLikeSp621e;

  /// True when it speaks the ELK/MELK format rather than BanlanX.
  bool get isMelk => Melk.looksLikeMelk(name);

  String get id => device.remoteId.str;
}

/// Owns the BLE link to an SP621E and nothing else: scanning, connecting,
/// framing, and the serialised write path.
///
/// Deliberately has no opinion about lightning. That lives in the thunder
/// engine, which drives this class through [send] and the typed helpers.
class Sp621eConnection extends ChangeNotifier implements LedDevice {
  @override
  bool get supportsSegments => true;

  @override
  String get label => _status != null || _device != null
      ? (_device?.platformName.isNotEmpty == true
          ? _device!.platformName
          : 'SP621E')
      : 'SP621E';

  /// Applies a travelling block in one call, so callers do not have to know
  /// that it takes four separate frames.
  @override
  Future<void> setSegment({
    required int effect,
    required int speed,
    required int length,
    required int brightness,
  }) async {
    // Order matters: the controller applies speed and length to whatever
    // effect is current, so the effect is selected first.
    await setEffect(effect);
    await setSpeed(speed);
    await setLength(length);
    await setBrightness(brightness);
  }

  Sp621eLinkState _link = Sp621eLinkState.disconnected;
  Sp621eLinkState get link => _link;
  @override
  bool get isConnected => _link == Sp621eLinkState.connected;

  final List<Sp621eCandidate> _candidates = [];
  List<Sp621eCandidate> get candidates => List.unmodifiable(_candidates);

  final List<Sp621eLogEntry> _log = [];
  List<Sp621eLogEntry> get log => List.unmodifiable(_log);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _channel;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _notifySub;

  /// Which controller this link is pointed at, or null when idle. Used to
  /// avoid connecting the same device twice into different slots.
  @override
  String? get deviceId => _device?.remoteId.str;

  /// The controller's last reported state. Null until it answers a query.
  Sp621eStatus? _status;
  Sp621eStatus? get status => _status;

  // ---------------------------------------------------------------------
  // Shadow state
  //
  // Every write is an acknowledged GATT operation costing tens of
  // milliseconds, and a lightning stroke has a budget of about a hundred.
  // Tracking what the controller was last told lets the write path drop
  // commands that would change nothing, which is the single biggest saving
  // available on this link.
  // ---------------------------------------------------------------------
  int? _lastEffect;
  int? _lastSpeed;
  int? _lastLength;
  int? _lastBrightness;
  int? _lastR;
  int? _lastG;
  int? _lastB;
  bool? _lastPower;

  int _writesSent = 0;
  int _writesSkipped = 0;

  /// Rolling measurement of how long one acknowledged write actually takes.
  ///
  /// The planner needs this to lay out a strike it can keep up with, and it
  /// varies by an order of magnitude with the negotiated connection interval,
  /// so it is measured rather than assumed.
  final List<int> _writeSamples = [];
  int _measuredWriteMs = 40;

  @override
  int get measuredWriteMs => _measuredWriteMs;

  void _recordWriteTime(int micros) {
    _writeSamples.add(micros ~/ 1000);
    if (_writeSamples.length > 40) _writeSamples.removeAt(0);
    if (_writeSamples.length < 4) return;

    // The median ignores the occasional stalled write, which would otherwise
    // drag the estimate up and make every plan needlessly sparse.
    final sorted = List<int>.from(_writeSamples)..sort();
    _measuredWriteMs = sorted[sorted.length ~/ 2].clamp(8, 400);
  }

  /// How many writes actually reached the controller, and how many were
  /// elided as redundant. Surfaced in the UI because the ratio is the best
  /// available signal for whether a strike will hit its timings.
  @override
  int get writesSent => _writesSent;
  @override
  int get writesSkipped => _writesSkipped;

  @override
  void resetWriteStats() {
    _writesSent = 0;
    _writesSkipped = 0;
  }

  /// Forgets the shadow state, so the next command is sent even if it matches
  /// what we believe the controller holds. Used after a reconnect, and before
  /// a strike, where a missed write is worse than a redundant one.
  @override
  void invalidateShadow() {
    _lastEffect = null;
    _lastSpeed = null;
    _lastLength = null;
    _lastBrightness = null;
    _lastR = null;
    _lastG = null;
    _lastB = null;
    _lastPower = null;
  }

  void _addLog(String text, {bool outbound = true}) {
    // Mirrored to the debug console so the link can be followed over adb as
    // well as on the phone.
    if (kDebugMode) debugPrint('[SP621E] $text');
    _log.add(Sp621eLogEntry(text, outbound: outbound));
    if (_log.length > 400) {
      _log.removeRange(0, _log.length - 400);
    }
  }

  void _setLink(Sp621eLinkState state) {
    if (_link == state) return;
    _link = state;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Scanning and connecting
  // ---------------------------------------------------------------------

  Future<bool> _ensurePermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scan = results[Permission.bluetoothScan]?.isGranted ?? false;
    final connect = results[Permission.bluetoothConnect]?.isGranted ?? false;
    final location = results[Permission.locationWhenInUse]?.isGranted ?? false;

    // Android 12+ grants scan/connect; 11 and below only ever return scan
    // results when location is granted.
    return (scan && connect) || location;
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 8)}) async {
    if (!await _ensurePermissions()) {
      _addLog('permission denied, cannot scan', outbound: false);
      notifyListeners();
      return;
    }

    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await FlutterBluePlus.turnOn();
      }
    }

    _candidates.clear();
    _dumped.clear();
    _setLink(Sp621eLinkState.scanning);

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen(
      _onScanResults,
      onError: (Object e) {
        _addLog('scan error: $e', outbound: false);
        _setLink(Sp621eLinkState.disconnected);
      },
    );

    await FlutterBluePlus.startScan(timeout: timeout);
    await FlutterBluePlus.isScanning.where((on) => !on).first;

    await _scanSub?.cancel();
    _scanSub = null;
    if (_link == Sp621eLinkState.scanning) {
      _setLink(Sp621eLinkState.disconnected);
    }
  }

  /// Advertisements already dumped to the debug log, so a device that keeps
  /// advertising does not fill the log with the same line.
  final Set<String> _dumped = {};

  void _onScanResults(List<ScanResult> results) {
    var changed = false;

    for (final result in results) {
      final adv = result.advertisementData;

      // Identifying the controller is the first thing that goes wrong with
      // these devices, so every new advertisement is dumped once in full.
      if (kDebugMode && _dumped.add(result.device.remoteId.str)) {
        final manufacturers = adv.manufacturerData.entries
            .map((e) => '${e.key}(0x${e.key.toRadixString(16)})='
                '${BanlanX2.hex(e.value)}')
            .join(', ');
        debugPrint(
          '[SCAN] ${result.device.remoteId.str} '
          'name="${adv.advName}" platform="${result.device.platformName}" '
          'rssi=${result.rssi} '
          'services=${adv.serviceUuids} '
          'manufacturer=[$manufacturers]',
        );
      }
      final name = adv.advName.isNotEmpty
          ? adv.advName
          : (result.device.platformName.isNotEmpty
              ? result.device.platformName
              : 'Unknown');

      final manufacturerData = adv.manufacturerData[BanlanX2.manufacturerId];

      // Two families, identified two different ways: BanlanX controllers carry
      // a company ID, while ELK/MELK ones advertise nothing but a name.
      final model = BanlanX2.modelFor(manufacturerData) ??
          (Melk.looksLikeMelk(name) ? name.trim() : null);

      final candidate = Sp621eCandidate(
        device: result.device,
        name: name,
        rssi: result.rssi,
        looksLikeSp621e: model != null,
        model: model,
        manufacturerData: manufacturerData,
      );

      final index = _candidates.indexWhere((c) => c.id == candidate.id);
      if (index >= 0) {
        _candidates[index] = candidate;
      } else {
        _candidates.add(candidate);
      }
      changed = true;
    }

    if (changed) {
      // Known controllers first, then by signal strength.
      _candidates.sort((a, b) {
        if (a.looksLikeSp621e != b.looksLikeSp621e) {
          return a.looksLikeSp621e ? -1 : 1;
        }
        return b.rssi.compareTo(a.rssi);
      });
      notifyListeners();
    }
  }

  @override
  Future<void> connect(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;

    _setLink(Sp621eLinkState.connecting);
    _device = device;

    await _connSub?.cancel();
    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _channel = null;
        _status = null;
        invalidateShadow();
        _addLog('disconnected', outbound: false);
        _setLink(Sp621eLinkState.disconnected);
      }
    });

    try {
      await device.connect(
        timeout: const Duration(seconds: 12),
        license: License.nonprofit,
      );
      await _bind(device);
    } catch (e) {
      _addLog('connect failed: $e', outbound: false);
      _setLink(Sp621eLinkState.disconnected);
    }
  }

  /// Finds FFE0/FFE1, subscribes to notifications, and asks the controller
  /// what state it is in.
  Future<void> _bind(BluetoothDevice device) async {
    final services = await device.discoverServices();

    BluetoothCharacteristic? channel;
    for (final service in services) {
      if (service.serviceUuid != Guid(BanlanX2.serviceUuid)) continue;
      for (final c in service.characteristics) {
        if (c.characteristicUuid == Guid(BanlanX2.writeUuid)) {
          channel = c;
          break;
        }
      }
    }

    if (channel == null) {
      _addLog(
        'no FFE0/FFE1 characteristic, this is not a BanlanX v2 controller',
        outbound: false,
      );
      await device.disconnect();
      _setLink(Sp621eLinkState.disconnected);
      return;
    }

    _channel = channel;
    invalidateShadow();

    // Android defaults to a relaxed connection interval, which on this
    // controller measured out at about 120ms per acknowledged write. Asking
    // for the high-priority interval (roughly 11-15ms) is the single largest
    // saving available, and a strike is entirely bounded by write latency.
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
        _addLog('requested high connection priority', outbound: false);
      } catch (e) {
        // Not fatal: the link still works, just slower.
        _addLog('connection priority request failed: $e', outbound: false);
      }
    }

    // FFE1 is both the write and the notify handle; there is no separate read
    // characteristic on these controllers.
    if (channel.properties.notify || channel.properties.indicate) {
      try {
        await channel.setNotifyValue(true);
        await _notifySub?.cancel();
        _notifySub = channel.onValueReceived.listen(_onNotification);
      } catch (e) {
        _addLog('notify subscribe failed: $e', outbound: false);
      }
    }

    _setLink(Sp621eLinkState.connected);
    _addLog('connected', outbound: false);

    await send(BanlanX2.queryState());
  }

  void _onNotification(List<int> data) {
    _addLog('<- ${BanlanX2.hex(data)}', outbound: false);

    final status = Sp621eStatus.parse(data);
    if (status == null) return;

    _status = status;

    // The controller just told us the truth, so the shadow can be trusted
    // again, and corrected where our guess was wrong.
    _lastPower = status.isOn;
    _lastEffect = status.effect;
    _lastBrightness = status.brightness;
    _lastSpeed = status.speed;
    _lastLength = status.length;
    _lastR = status.r;
    _lastG = status.g;
    _lastB = status.b;

    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    await _scanSub?.cancel();
    await _notifySub?.cancel();
    await _connSub?.cancel();
    _scanSub = null;
    _notifySub = null;
    _connSub = null;

    try {
      await _device?.disconnect();
    } catch (_) {
      // Already gone; nothing useful to do.
    }

    _device = null;
    _channel = null;
    _status = null;
    invalidateShadow();
    _setLink(Sp621eLinkState.disconnected);
  }

  // ---------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------

  Future<void> _chain = Future<void>.value();

  /// Queues one frame. Writes are serialised because overlapping GATT writes
  /// to a single characteristic are not safe, and acknowledged because these
  /// controllers drop a meaningful share of write-without-response traffic.
  Future<void> send(List<int> frame) {
    _chain = _chain.then((_) async {
      final channel = _channel;
      if (channel == null || !isConnected) return;

      final timer = Stopwatch()..start();
      try {
        await channel.write(frame, withoutResponse: false);
        timer.stop();
        _recordWriteTime(timer.elapsedMicroseconds);
        _writesSent++;
        _addLog('-> ${BanlanX2.hex(frame)}');
      } catch (e) {
        _addLog('write failed ${BanlanX2.hex(frame)}: $e', outbound: false);
      }
    });
    return _chain;
  }

  /// Waits for every queued write to drain.
  @override
  Future<void> flush() => _chain;

  // ---------------------------------------------------------------------
  // Typed commands
  //
  // Each one elides the write when the controller already holds the value.
  // ---------------------------------------------------------------------

  @override
  Future<void> setPower(bool on) async {
    if (_lastPower == on) {
      _writesSkipped++;
      return;
    }
    _lastPower = on;
    await send(BanlanX2.power(on));
  }

  Future<void> setEffect(int effect) async {
    if (_lastEffect == effect) {
      _writesSkipped++;
      return;
    }
    _lastEffect = effect;
    // Leaving the solid effect invalidates the colour the controller holds,
    // since a dynamic effect paints its own.
    if (effect != Sp621eEffects.solid) {
      _lastR = null;
      _lastG = null;
      _lastB = null;
    }
    await send(BanlanX2.effect(effect));
  }

  @override
  Future<void> setBrightness(int level) async {
    final value = level.clamp(0, 255).toInt();
    if (_lastBrightness == value) {
      _writesSkipped++;
      return;
    }
    _lastBrightness = value;
    await send(BanlanX2.brightness(value));
  }

  Future<void> setSpeed(int speed) async {
    final value = speed.clamp(1, BanlanX2.maxEffectSpeed).toInt();
    if (_lastSpeed == value) {
      _writesSkipped++;
      return;
    }
    _lastSpeed = value;
    await send(BanlanX2.effectSpeed(value));
  }

  Future<void> setLength(int length) async {
    final value = length.clamp(1, BanlanX2.maxEffectLength).toInt();
    if (_lastLength == value) {
      _writesSkipped++;
      return;
    }
    _lastLength = value;
    await send(BanlanX2.effectLength(value));
  }

  /// Sets an RGB colour, switching to the solid effect first if needed. The
  /// controller ignores colour frames while a dynamic effect is running.
  @override
  Future<void> setColor(int r, int g, int b, {int? level}) async {
    await setEffect(Sp621eEffects.solid);

    final brightness = (level ?? _lastBrightness ?? 255).clamp(0, 255).toInt();

    if (_lastR == r &&
        _lastG == g &&
        _lastB == b &&
        _lastBrightness == brightness) {
      _writesSkipped++;
      return;
    }

    _lastR = r;
    _lastG = g;
    _lastB = b;
    _lastBrightness = brightness;

    await send(BanlanX2.rgb(r, g, b, brightness));
  }

  /// Sets the strip's colour channel order, 0-5, indexing [BanlanX2.chipOrders].
  Future<void> setChipOrder(int order) async {
    final value = order.clamp(0, BanlanX2.chipOrders.length - 1).toInt();
    _chipOrder = value;
    notifyListeners();
    await send(BanlanX2.chipOrder(value));
  }

  int _chipOrder = 0;
  int get chipOrder => _status?.chipOrder ?? _chipOrder;

  Future<void> requestState() => send(BanlanX2.queryState());

  void clearLog() {
    _log.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _notifySub?.cancel();
    _connSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }
}
