import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/led_controller_state.dart';
import '../models/led_layout.dart';
import '../audio/thunder_player.dart';
import '../lightning/lightning_engine.dart';

class Sp621eBleService extends ChangeNotifier {
  Sp621eControllerState _state = const Sp621eControllerState();
  Sp621eControllerState get state => _state;

  static final Guid serviceUuid = Guid('0000FFE0-0000-1000-8000-00805F9B34FB');
  static final Guid writeUuid = Guid('0000FFE1-0000-1000-8000-00805F9B34FB');

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  final List<BluetoothDevice> _discoveredDevices = [];
  List<BluetoothDevice> get discoveredDevices => _discoveredDevices;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;

  /// Update state and notify listeners
  void _updateState(Sp621eControllerState newState) {
    _state = newState;
    notifyListeners();
  }

  Future<bool> _requestPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scan = results[Permission.bluetoothScan];
    final connect = results[Permission.bluetoothConnect];
    final location = results[Permission.locationWhenInUse];

    return ((scan?.isGranted ?? false) && (connect?.isGranted ?? false)) ||
        (location?.isGranted ?? false);
  }

  void scan() async {
    if (!await _requestPermissions()) return;

    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await FlutterBluePlus.turnOn();
      }
    }

    _updateState(_state.copyWith(connectionState: Sp621eConnectionState.scanning));
    _discoveredDevices.clear();
    notifyListeners();

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.device.platformName.isNotEmpty ? result.device.platformName : result.advertisementData.advName;
        final index = _discoveredDevices.indexWhere((d) => d.remoteId == result.device.remoteId);
        if (index >= 0) {
          _discoveredDevices[index] = result.device;
        } else {
          _discoveredDevices.add(result.device);
        }
        notifyListeners();
      }
    }, onError: (error) {
      debugPrint('Scan error: $error');
      _updateState(_state.copyWith(connectionState: Sp621eConnectionState.disconnected));
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    _scanSub?.cancel();
    if (_state.connectionState == Sp621eConnectionState.scanning) {
      _updateState(_state.copyWith(connectionState: Sp621eConnectionState.disconnected));
    }
  }

  Future<void> connect(String deviceId) async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    
    _updateState(_state.copyWith(connectionState: Sp621eConnectionState.connecting));

    final device = BluetoothDevice.fromId(deviceId);
    
    _connectionSub?.cancel();
    _connectionSub = device.connectionState.listen((connectionState) async {
      if (connectionState == BluetoothConnectionState.connected) {
        _connectedDevice = device;
        _updateState(_state.copyWith(connectionState: Sp621eConnectionState.connected));
        
        // Discover services and find the write characteristic
        try {
          final services = await device.discoverServices();
          debugPrint('[SP621E] Discovered ${services.length} services');
          
          // Log ALL services and characteristics for debugging
          for (final service in services) {
            debugPrint('[SP621E] Service: ${service.serviceUuid}');
            for (final c in service.characteristics) {
              debugPrint('[SP621E]   Char: ${c.characteristicUuid} '
                  'props: write=${c.properties.write} '
                  'writeNoResp=${c.properties.writeWithoutResponse} '
                  'read=${c.properties.read} '
                  'notify=${c.properties.notify}');
            }
          }
          
          // Strategy: First try exact FFE0/FFE1 match, then try FFE5/FFE9, 
          // then fall back to any writable characteristic on a non-generic service
          _writeCharacteristic = _findCharacteristic(services, serviceUuid, writeUuid);
          
          if (_writeCharacteristic == null) {
            // Try alternate BanlanX UUIDs (FFE5 service, FFE9 char)
            final altServiceUuid = Guid('0000FFE5-0000-1000-8000-00805F9B34FB');
            final altWriteUuid = Guid('0000FFE9-0000-1000-8000-00805F9B34FB');
            _writeCharacteristic = _findCharacteristic(services, altServiceUuid, altWriteUuid);
          }
          
          if (_writeCharacteristic == null) {
            // Fallback: find any writable characteristic on a non-standard service
            for (final service in services) {
              // Skip GATT standard services (1800, 1801)
              final sUuid = service.serviceUuid.toString().toUpperCase();
              if (sUuid.startsWith('00001800') || sUuid.startsWith('00001801')) continue;
              
              for (final c in service.characteristics) {
                if (c.properties.writeWithoutResponse || c.properties.write) {
                  _writeCharacteristic = c;
                  debugPrint('[SP621E] Fallback: using ${c.characteristicUuid} on ${service.serviceUuid}');
                  break;
                }
              }
              if (_writeCharacteristic != null) break;
            }
          }
          
          if (_writeCharacteristic != null) {
            debugPrint('[SP621E] CONNECTED - using characteristic: ${_writeCharacteristic!.characteristicUuid}');
            // Flush old state and initialize with our commands
            await _initializeController();
          } else {
            debugPrint('[SP621E] ERROR: No writable characteristic found on any service!');
          }
        } catch (e) {
          debugPrint('[SP621E] Service discovery failed: $e');
        }
      } else if (connectionState == BluetoothConnectionState.disconnected) {
        _connectedDevice = null;
        _writeCharacteristic = null;
        _updateState(_state.copyWith(connectionState: Sp621eConnectionState.disconnected));
      }
    }, onError: (error) {
      debugPrint('[SP621E] Connect error: $error');
      _connectedDevice = null;
      _writeCharacteristic = null;
      _updateState(_state.copyWith(connectionState: Sp621eConnectionState.disconnected));
    });

    try {
      await device.connect(timeout: const Duration(seconds: 10), license: License.nonprofit);
    } catch (e) {
      debugPrint('[SP621E] Connect exception: $e');
      _updateState(_state.copyWith(connectionState: Sp621eConnectionState.disconnected));
    }
  }

  /// Find a characteristic by service and characteristic UUID
  BluetoothCharacteristic? _findCharacteristic(
      List<BluetoothService> services, Guid sUuid, Guid cUuid) {
    for (final service in services) {
      if (service.serviceUuid == sUuid) {
        for (final c in service.characteristics) {
          if (c.characteristicUuid == cUuid) {
            debugPrint('[SP621E] Matched: service=$sUuid char=$cUuid');
            return c;
          }
        }
      }
    }
    return null;
  }

  Future<void> setLedCount(int count) async {
    // 288 = 0x0120
    final highByte = (count >> 8) & 0xFF;
    final lowByte = count & 0xFF;
    
    // Most common BanlanX length setting command: 7E 04 03 High Low 00 FF 00 EF
    await _writeCommand([0x7E, 0x04, 0x03, highByte, lowByte, 0x00, 0xFF, 0x00, 0xEF]);
    // Alternative format just in case
    await _writeCommand([0x7E, 0x00, 0x03, highByte, lowByte, 0x00, 0x00, 0x00, 0xEF]);
  }

  Future<void> _initializeController() async {
  debugPrint('[SP621E] Initializing BanlanX v2 controller...');

  // SP621E BanlanX v2.
  await requestState();

  await Future.delayed(
    const Duration(milliseconds: 100),
  );

  await powerOn();

  debugPrint('[SP621E] Initialization complete');
}

  Future<void> testProtocol(int protocolNumber) async {
    debugPrint('[SP621E] TESTING PROTOCOL $protocolNumber (Target: Solid RED)');

    final List<List<List<int>>> protocols = [
      // Protocol 1: Standard 7E frame (Format 1)
      [
        [0x7E, 0x04, 0x04, 0x01, 0x00, 0x00, 0xFF, 0x00, 0xEF], // Power On
        [0x7E, 0x07, 0x05, 0x03, 0xFF, 0x00, 0x00, 0x00, 0xEF], // Red
      ],
      // Protocol 2: Standard 7E frame (Format 2)
      [
        [0x7E, 0x00, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0xEF], // Power On
        [0x7E, 0x00, 0x05, 0x03, 0xFF, 0x00, 0x00, 0x00, 0xEF], // Red
      ],
      // Protocol 3: 7E frame with 0x10 modifier (Addressable variant)
      [
        [0x7E, 0x04, 0x04, 0x01, 0x00, 0x00, 0xFF, 0x00, 0xEF], // Power On
        [0x7E, 0x07, 0x05, 0x03, 0xFF, 0x00, 0x00, 0x10, 0xEF], // Red
      ],
      // Protocol 4: 7E frame with 0x10 modifier (Format 2)
      [
        [0x7E, 0x00, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0xEF], // Power On
        [0x7E, 0x00, 0x05, 0x03, 0xFF, 0x00, 0x00, 0x10, 0xEF], // Red
      ],
      // Protocol 5: Elk-Bledom (Simple)
      [
        [0xCC, 0x23, 0x33], // Power On
        [0x56, 0xFF, 0x00, 0x00, 0x00, 0xF0, 0xAA], // Red
      ],
      // Protocol 6: Triones / HappyLighting
      [
        [0xCC, 0x23, 0x33], // Power On
        [0x56, 0xFF, 0x00, 0x00, 0x00, 0xF0, 0xAA], // Red (Triones uses this too)
      ],
      // Protocol 7: SP621E / BanlanX variant (Usually FFE5/FFE9 but just in case)
      [
        [0x69, 0x96, 0x02, 0x01, 0x01], // Power On
        [0x69, 0x96, 0x06, 0x01, 0x01, 0xFF, 0x00, 0x00], // Red
      ],
      // Protocol 8: ZENGGE variant
      [
        [0x71, 0x23, 0x0F], // Power On
        [0x31, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x0F], // Red
      ],
      // Protocol 9: Another 7E variation (No prefix length)
      [
        [0x7E, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0xEF], // Power On
        [0x7E, 0x05, 0x03, 0xFF, 0x00, 0x00, 0x00, 0xEF], // Red
      ],
      // Protocol 10: FFF0/FFF3 raw color
      [
        [0x81, 0x01, 0x01, 0x00],
        [0x81, 0x00, 0x00, 0x01, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00], // Red
      ],
      // Protocol 11: 16 byte BanlanX FFE9 format (sometimes sent on FFF3)
      [
        [0xBB, 0x00, 0x06, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], // Power On
        [0xBB, 0x00, 0x06, 0x83, 0x00, 0x00, 0x01, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00], // Red
      ],
      // Protocol 12: Generic raw bytes
      [
        [0x01, 0xFF, 0x00, 0x00], // Red
        [0xFF, 0x00, 0x00, 0x00], // Red
      ]
    ];

    if (protocolNumber < 1 || protocolNumber > protocols.length) return;

    for (final cmd in protocols[protocolNumber - 1]) {
      await _writeCommand(cmd);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    
    debugPrint('[SP621E] TEST COMPLETE.');
  }

  Future<void> disconnect() async {
    _scanSub?.cancel();
    _connectionSub?.cancel();
    await _connectedDevice?.disconnect();
    _connectedDevice = null;
    _writeCharacteristic = null;
    _updateState(_state.copyWith(connectionState: Sp621eConnectionState.disconnected));
  }

// ============================================================
// SP621E / BanlanX v2 protocol
// ============================================================

static const Duration _bleCommandGap =
    Duration(milliseconds: 35);

static const int _solidEffect = 0xBE;

// Confirmed BanlanX v2 effect:
// 0x8D = White Segment Spin
static const int _whiteSegmentSpinEffect = 0x8D;

// 80 cm visible row @ 60 LED/m = 48 LEDs.
static const int _rowBatchLength = 48;

Future<void> _writeChain = Future<void>.value();

Future<void> _writeCommand(List<int> commandBytes) {
  _writeChain = _writeChain.then((_) async {
    final characteristic = _writeCharacteristic;

    if (characteristic == null) {
      debugPrint(
        '[SP621E] WRITE SKIPPED - no characteristic',
      );
      return;
    }

    if (_state.connectionState !=
        Sp621eConnectionState.connected) {
      debugPrint(
        '[SP621E] WRITE SKIPPED - not connected',
      );
      return;
    }

    final hex = commandBytes
        .map(
          (b) => b
              .toRadixString(16)
              .padLeft(2, '0')
              .toUpperCase(),
        )
        .join(' ');

    try {
      final withoutResponse =
          characteristic.properties.writeWithoutResponse;

      await characteristic.write(
        commandBytes,
        withoutResponse: withoutResponse,
      );

      debugPrint('[SP621E] WRITE: $hex');

      // SP621E behaves much more reliably when commands are
      // not dumped into the GATT characteristic back-to-back.
      await Future.delayed(_bleCommandGap);
    } catch (e) {
      debugPrint(
        '[SP621E] WRITE FAILED: $hex error=$e',
      );
    }
  });

  return _writeChain;
}

// ============================================================
// Basic controller commands
// ============================================================

Future<void> powerOn() async {
  await _writeCommand([
    0xA0,
    0x62,
    0x01,
    0x01,
  ]);

  _updateState(
    _state.copyWith(isOn: true),
  );
}

Future<void> powerOff() async {
  await _writeCommand([
    0xA0,
    0x62,
    0x01,
    0x00,
  ]);

  _updateState(
    _state.copyWith(isOn: false),
  );
}

Future<void> setBrightness(int brightness) async {
  final value =
      brightness.clamp(0, 255).toInt();

  await _writeCommand([
    0xA0,
    0x66,
    0x01,
    value,
  ]);

  _updateState(
    _state.copyWith(
      brightness: value,
    ),
  );
}

Future<void> setEffect(int effect) async {
  final value =
      effect.clamp(0, 255).toInt();

  await _writeCommand([
    0xA0,
    0x63,
    0x01,
    value,
  ]);

  _updateState(
    _state.copyWith(effect: value),
  );
}

Future<void> setEffectSpeed(int speed) async {
  final value =
      speed.clamp(1, 10).toInt();

  await _writeCommand([
    0xA0,
    0x67,
    0x01,
    value,
  ]);

  _updateState(
    _state.copyWith(
      effectSpeed: value,
    ),
  );
}

Future<void> setEffectLength(int length) async {
  final value =
      length.clamp(1, 150).toInt();

  await _writeCommand([
    0xA0,
    0x68,
    0x01,
    value,
  ]);

  _updateState(
    _state.copyWith(
      effectLength: value,
    ),
  );
}

Future<void> requestState() async {
  await _writeCommand([
    0xA0,
    0x70,
    0x00,
  ]);
}

// ============================================================
// Static RGB
// ============================================================

Future<void> setColor(
  int r,
  int g,
  int b, {
  int? brightness,
}) async {
  final red = r.clamp(0, 255).toInt();
  final green = g.clamp(0, 255).toInt();
  final blue = b.clamp(0, 255).toInt();

  final level = (brightness ?? _state.brightness)
      .clamp(0, 255)
      .toInt();

  // Enter solid RGB mode.
  await _writeCommand([
    0xA0,
    0x63,
    0x01,
    _solidEffect,
  ]);

  // BanlanX RGB command.
  await _writeCommand([
    0xA0,
    0x69,
    0x04,
    red,
    green,
    blue,
    level,
  ]);

  _updateState(
    _state.copyWith(
      r: red,
      g: green,
      b: blue,
      brightness: level,
      effect: _solidEffect,
    ),
  );
}

Future<void> setStaticMode() async {
  await setEffect(_solidEffect);
}

Future<void> flashWhite(int brightness) async {
  await setColor(
    245,
    250,
    255,
    brightness: brightness,
  );
}

// ============================================================
// Lightning helpers
// ============================================================

Timer? _stormTimer;

final math.Random _random = math.Random();

Future<void> _goDark(int milliseconds) async {
  // Switching to solid black is deliberate.
  //
  // It stops the previous moving segment so that the next
  // White Segment Spin command begins as a visually separate
  // lightning batch.
  await setColor(
    0,
    0,
    0,
    brightness: 0,
  );

  await Future.delayed(
    Duration(milliseconds: milliseconds),
  );
}

/// Runs one moving white lightning batch.
///
/// SP621E cannot address arbitrary ranges such as LEDs 60-107
/// directly. Instead its firmware moves a white segment through
/// the continuous strip.
///
/// 48 LEDs corresponds to one 80 cm visible row.
Future<void> _runBatchStrike({
  required double intensity,
  int segmentLength = _rowBatchLength,
  int? visualDurationMs,
  int? speed,
}) async {
  final actualIntensity =
      intensity.clamp(0.0, 1.0);

  final brightness =
      (255 * actualIntensity)
          .round()
          .clamp(1, 255)
          .toInt();

  final actualLength =
      segmentLength.clamp(8, 80).toInt();

  final actualSpeed =
      (speed ?? (8 + _random.nextInt(3)))
          .clamp(1, 10)
          .toInt();

  // Set color to white first, so the segment spin effect isn't black!
  // This temporarily switches to solid mode, but the next command
  // instantly switches it to the spin effect.
  await _writeCommand([
    0xA0,
    0x69,
    0x04,
    255,
    255,
    255,
    brightness,
  ]);

  // White Segment Spin.
  await _writeCommand([
    0xA0,
    0x63,
    0x01,
    _whiteSegmentSpinEffect,
  ]);

  await _writeCommand([
    0xA0,
    0x68,
    0x01,
    actualLength,
  ]);

  await _writeCommand([
    0xA0,
    0x67,
    0x01,
    actualSpeed,
  ]);

  await _writeCommand([
    0xA0,
    0x66,
    0x01,
    brightness,
  ]);

  _updateState(
    _state.copyWith(
      effect: _whiteSegmentSpinEffect,
      effectLength: actualLength,
      effectSpeed: actualSpeed,
      brightness: brightness,
    ),
  );

  final duration =
      visualDurationMs ??
      (115 + _random.nextInt(90));

  debugPrint(
    '[LIGHTNING] batch '
    'len=$actualLength '
    'speed=$actualSpeed '
    'brightness=$brightness '
    'duration=${duration}ms',
  );

  await Future.delayed(
    Duration(milliseconds: duration),
  );
}

/// One short full-room impact flash.
///
/// This is deliberately different from [_runBatchStrike].
/// The moving batches create spatial motion; the impact flash
/// simulates the room being illuminated by the main discharge.
Future<void> _impactFlash({
  required double intensity,
  int? durationMs,
}) async {
  final level =
      (255 * intensity.clamp(0.0, 1.0))
          .round()
          .clamp(1, 255)
          .toInt();

  await setColor(
    245,
    250,
    255,
    brightness: level,
  );

  final duration =
      (durationMs ??
      (38 + _random.nextInt(25))) + 20;

  debugPrint(
    '[LIGHTNING] IMPACT '
    'brightness=$level '
    'duration=${duration}ms',
  );

  await Future.delayed(
    Duration(milliseconds: duration),
  );
}

ThunderDistance _audioDistance(
  LightningProfile profile,
) {
  switch (profile) {
    case LightningProfile.distant:
      return ThunderDistance.far;

    case LightningProfile.normal:
      return ThunderDistance.mid;

    case LightningProfile.close:
    case LightningProfile.violent:
      return ThunderDistance.close;
  }
}

Duration _thunderDelay(
  LightningProfile profile,
) {
  switch (profile) {
    case LightningProfile.distant:
      return Duration(
        milliseconds:
            2200 + _random.nextInt(2001),
      );

    case LightningProfile.normal:
      return Duration(
        milliseconds:
            700 + _random.nextInt(901),
      );

    case LightningProfile.close:
      return Duration(
        milliseconds:
            180 + _random.nextInt(371),
      );

    case LightningProfile.violent:
      return Duration(
        milliseconds:
            100 + _random.nextInt(301),
      );
  }
}

// ============================================================
// Main realistic lightning event
// ============================================================

Future<void> triggerThunder(
  ThunderPlayer thunderPlayer, {
  LightningProfile? profile,
}) async {
  if (_state.connectionState !=
      Sp621eConnectionState.connected) {
    debugPrint(
      '[LIGHTNING] ignored - SP621E not connected',
    );
    return;
  }

  final selected =
      profile ?? LightningProfile.normal;

  // Save the user's actual background before the lightning
  // engine starts changing controller state.
  final originalIsOn = _state.isOn;
  final originalBrightness = _state.brightness;

  final originalR = _state.r;
  final originalG = _state.g;
  final originalB = _state.b;

  final originalEffect = _state.effect;
  final originalSpeed = _state.effectSpeed;
  final originalLength = _state.effectLength;

  final thunderDelay =
      _thunderDelay(selected);

  debugPrint(
    '[LIGHTNING] START '
    'profile=${selected.name} '
    'thunder=${thunderDelay.inMilliseconds}ms',
  );

  try {
    if (!originalIsOn) {
      await powerOn();
    }

    // --------------------------------------------------------
    // DISTANT
    // --------------------------------------------------------

    if (selected ==
        LightningProfile.distant) {
      thunderPlayer.playAfter(
        _audioDistance(selected),
        thunderDelay,
      );

      await _runBatchStrike(
        intensity:
            0.40 +
            (_random.nextDouble() * 0.20),
        segmentLength:
            24 + _random.nextInt(13),
        visualDurationMs:
            150 + _random.nextInt(80),
        speed: 7,
      );

      await _goDark(
        70 + _random.nextInt(60),
      );

      if (_random.nextDouble() < 0.55) {
        await _runBatchStrike(
          intensity:
              0.30 +
              (_random.nextDouble() * 0.18),
          segmentLength:
              18 + _random.nextInt(15),
          visualDurationMs:
              110 + _random.nextInt(80),
          speed: 6,
        );
      }

      return;
    }

    // --------------------------------------------------------
    // PRECURSOR
    // --------------------------------------------------------

    if (_random.nextDouble() < 0.50) {
      await _runBatchStrike(
        intensity:
            0.25 +
            (_random.nextDouble() * 0.25),
        segmentLength:
            18 + _random.nextInt(19),
        visualDurationMs:
            90 + _random.nextInt(70),
      );

      await _goDark(
        35 + _random.nextInt(40),
      );
    }

    // --------------------------------------------------------
    // MAIN MOVING BATCH
    // --------------------------------------------------------

    await _runBatchStrike(
      intensity:
          0.82 +
          (_random.nextDouble() * 0.18),
      segmentLength: _rowBatchLength,
      visualDurationMs:
          120 + _random.nextInt(70),
      speed: 10,
    );

    await _goDark(
      30 + _random.nextInt(35),
    );

    // --------------------------------------------------------
    // MAIN RETURN-STROKE IMPACT
    //
    // Intentionally illuminates the entire wall very briefly.
    // --------------------------------------------------------

    thunderPlayer.playAfter(
      _audioDistance(selected),
      thunderDelay,
    );

    await _impactFlash(
      intensity:
          0.92 +
          (_random.nextDouble() * 0.08),
      durationMs:
          38 + _random.nextInt(25),
    );

    await _goDark(
      35 + _random.nextInt(35),
    );

    // --------------------------------------------------------
    // FIRST RESTRIKE / SECOND BATCH
    // --------------------------------------------------------

    if (_random.nextDouble() < 0.88) {
      await _runBatchStrike(
        intensity:
            0.55 +
            (_random.nextDouble() * 0.25),
        segmentLength:
            28 + _random.nextInt(21),
        visualDurationMs:
            90 + _random.nextInt(65),
        speed:
            8 + _random.nextInt(3),
      );

      await _goDark(
        35 + _random.nextInt(50),
      );
    }

    // --------------------------------------------------------
    // Close and violent strikes get an additional return stroke.
    // --------------------------------------------------------

    if (selected == LightningProfile.close ||
        selected == LightningProfile.violent) {
      thunderPlayer.playAfter(
      _audioDistance(selected),
      thunderDelay,
    );

    await _impactFlash(
        intensity:
            0.62 +
            (_random.nextDouble() * 0.30),
        durationMs:
            28 + _random.nextInt(24),
      );

      await _goDark(
        30 + _random.nextInt(40),
      );
    }

    // --------------------------------------------------------
    // SECOND MOVING RESTRIKE
    // --------------------------------------------------------

    final secondaryProbability =
        selected == LightningProfile.violent
            ? 0.90
            : 0.48;

    if (_random.nextDouble() <
        secondaryProbability) {
      await _runBatchStrike(
        intensity:
            0.35 +
            (_random.nextDouble() * 0.30),
        segmentLength:
            18 + _random.nextInt(25),
        visualDurationMs:
            75 + _random.nextInt(65),
        speed:
            8 + _random.nextInt(3),
      );

      await _goDark(
        30 + _random.nextInt(55),
      );
    }

    // --------------------------------------------------------
    // Small final branch / flicker
    // --------------------------------------------------------

    final finalBranchChance =
        selected == LightningProfile.violent
            ? 0.75
            : 0.32;

    if (_random.nextDouble() <
        finalBranchChance) {
      await _runBatchStrike(
        intensity:
            0.20 +
            (_random.nextDouble() * 0.25),
        segmentLength:
            12 + _random.nextInt(19),
        visualDurationMs:
            65 + _random.nextInt(45),
        speed: 10,
      );

      await _goDark(
        30 + _random.nextInt(35),
      );
    }
  } finally {
    // ========================================================
    // Restore exactly what the user had before the lightning.
    // ========================================================

    debugPrint('[LIGHTNING] RESTORE');

    if (!originalIsOn) {
      await powerOff();
    } else {
      await powerOn();

      await setBrightness(
        originalBrightness,
      );

      if (originalEffect == _solidEffect ||
          originalEffect == 0) {
        await setColor(
          originalR,
          originalG,
          originalB,
          brightness: originalBrightness,
        );
      } else {
        await setEffect(
          originalEffect,
        );

        await setEffectSpeed(
          originalSpeed,
        );

        await setEffectLength(
          originalLength,
        );

        await setBrightness(
          originalBrightness,
        );
      }
    }

    debugPrint('[LIGHTNING] COMPLETE');
  }
}

Future<void> restoreBackground() async {
  if (!_state.isOn) {
    await powerOff();
    return;
  }

  if (_state.effect == _solidEffect ||
      _state.effect == 0) {
    await setColor(
      _state.r,
      _state.g,
      _state.b,
      brightness: _state.brightness,
    );
  } else {
    await setEffect(_state.effect);
    await setEffectSpeed(_state.effectSpeed);
    await setEffectLength(_state.effectLength);
    await setBrightness(_state.brightness);
  }
}

  void toggleStormMode(ThunderPlayer player, bool enable) {
    if (enable) {
      _updateState(_state.copyWith(isStormMode: true));
      // Trigger immediately when enabled, then schedule the loop
      triggerThunder(player).then((_) {
        _scheduleNextStrike(player);
      });
    } else {
      _updateState(_state.copyWith(isStormMode: false));
      _stormTimer?.cancel();
      _stormTimer = null;
      restoreBackground();
    }
  }

  void _scheduleNextStrike(ThunderPlayer player) {
    if (!_state.isStormMode) return;
    
    // Random delay between 8 and 20 seconds for quicker testing
    final delaySeconds = 8 + _random.nextInt(13);
    
    _stormTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (!_state.isStormMode) return;
      
      await triggerThunder(player);
      _scheduleNextStrike(player);
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connectionSub?.cancel();
    _stormTimer?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }
}
