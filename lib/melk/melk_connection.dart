import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../led_device.dart';
import 'melk_protocol.dart';

/// A BLE link to an ELK-BLEDOM / MELK controller.
///
/// Structurally the same as the SP621E link — serialised writes, shadow state,
/// measured latency — but a different characteristic, a different frame format,
/// and a login handshake the controller insists on before it will listen.
///
/// It drives a plain RGB strip, so [supportsSegments] is false and every
/// command paints the whole run.
class MelkConnection extends ChangeNotifier implements LedDevice {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _channel;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  bool get supportsSegments => false;

  @override
  String get label => _device?.platformName.isNotEmpty == true
      ? _device!.platformName
      : 'MELK';

  @override
  String? get deviceId => _device?.remoteId.str;

  // Shadow state, so redundant writes can be dropped.
  bool? _lastPower;
  int? _lastLevel;
  int? _lastR;
  int? _lastG;
  int? _lastB;

  int _writesSent = 0;
  int _writesSkipped = 0;

  @override
  int get writesSent => _writesSent;

  @override
  int get writesSkipped => _writesSkipped;

  @override
  void resetWriteStats() {
    _writesSent = 0;
    _writesSkipped = 0;
  }

  @override
  void invalidateShadow() {
    _lastPower = null;
    _lastLevel = null;
    _lastR = null;
    _lastG = null;
    _lastB = null;
  }

  final List<int> _writeSamples = [];
  int _measuredWriteMs = 40;

  @override
  int get measuredWriteMs => _measuredWriteMs;

  void _recordWriteTime(int micros) {
    _writeSamples.add(micros ~/ 1000);
    if (_writeSamples.length > 40) _writeSamples.removeAt(0);
    if (_writeSamples.length < 4) return;
    final sorted = List<int>.from(_writeSamples)..sort();
    _measuredWriteMs = sorted[sorted.length ~/ 2].clamp(8, 400);
  }

  @override
  Future<void> connect(BluetoothDevice device) async {
    _device = device;

    await _connSub?.cancel();
    _connSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _connected = false;
        _channel = null;
        invalidateShadow();
        notifyListeners();
      }
    });

    try {
      await device.connect(
        timeout: const Duration(seconds: 12),
        license: License.nonprofit,
      );
      await _bind(device);
    } catch (e) {
      debugPrint('[MELK] connect failed: $e');
      _connected = false;
      notifyListeners();
    }
  }

  Future<void> _bind(BluetoothDevice device) async {
    final services = await device.discoverServices();

    BluetoothCharacteristic? channel;
    for (final service in services) {
      for (final c in service.characteristics) {
        if (c.characteristicUuid == Guid(Melk.writeUuid)) {
          channel = c;
          break;
        }
      }
      if (channel != null) break;
    }

    if (channel == null) {
      debugPrint('[MELK] no FFF3 characteristic; not an ELK/MELK controller');
      await device.disconnect();
      _connected = false;
      notifyListeners();
      return;
    }

    _channel = channel;
    _connected = true;
    invalidateShadow();

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
      } catch (_) {
        // Slower, but still works.
      }
    }

    // The controller ignores everything until this has gone out.
    for (final frame in Melk.loginSequence) {
      await _send(frame);
    }

    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    await _connSub?.cancel();
    _connSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {
      // Already gone.
    }
    _device = null;
    _channel = null;
    _connected = false;
    invalidateShadow();
    notifyListeners();
  }

  Future<void> _chain = Future<void>.value();

  Future<void> _send(List<int> frame) {
    _chain = _chain.then((_) async {
      final channel = _channel;
      if (channel == null || !_connected) return;

      final timer = Stopwatch()..start();
      try {
        // These controllers are written to without a response, which is what
        // the vendor app does and what the family's integrations use.
        await channel.write(frame, withoutResponse: true);
        timer.stop();
        _recordWriteTime(timer.elapsedMicroseconds);
        _writesSent++;
        if (kDebugMode) debugPrint('[MELK] -> ${Melk.hex(frame)}');
      } catch (e) {
        debugPrint('[MELK] write failed ${Melk.hex(frame)}: $e');
      }
    });
    return _chain;
  }

  @override
  Future<void> flush() => _chain;

  @override
  Future<void> setPower(bool on) async {
    if (_lastPower == on) {
      _writesSkipped++;
      return;
    }
    _lastPower = on;
    await _send(Melk.power(on));
  }

  @override
  Future<void> setBrightness(int level) async {
    final value = level.clamp(0, 255).toInt();
    if (_lastLevel == value) {
      _writesSkipped++;
      return;
    }
    _lastLevel = value;
    await _send(Melk.brightness(value));
  }

  @override
  Future<void> setColor(int r, int g, int b, {int? level}) async {
    final brightness = (level ?? _lastLevel ?? 255).clamp(0, 255).toInt();

    if (_lastR != r || _lastG != g || _lastB != b) {
      _lastR = r;
      _lastG = g;
      _lastB = b;
      await _send(Melk.rgb(r, g, b));
    } else {
      _writesSkipped++;
    }

    if (_lastLevel != brightness) {
      _lastLevel = brightness;
      await _send(Melk.brightness(brightness));
    }
  }

  @override
  Future<void> setSegment({
    required int effect,
    required int speed,
    required int length,
    required int brightness,
  }) async {
    // A plain RGB strip has no pixels to address. Doing nothing here is
    // deliberate: the fleet keeps this controller in step through brightness
    // and colour, which is all it can honour.
    _writesSkipped++;
  }

  Future<void> requestState() => _send(Melk.queryState());

  @override
  void dispose() {
    _connSub?.cancel();
    _device?.disconnect();
    super.dispose();
  }
}
