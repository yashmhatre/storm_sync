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
    debugPrint('[SP621E] Initializing controller...');
    
    // Set the LED length to 288 per the physical layout
    await setLedCount(288);
    await Future.delayed(const Duration(milliseconds: 100));

    // Force power on
    await powerOn();
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Set to white initially so the user can easily see effects
    await setColor(255, 255, 255);
    
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

  Future<void> _writeCommand(List<int> commandBytes) async {
    if (_writeCharacteristic == null) {
      debugPrint('[SP621E] WRITE SKIPPED - no characteristic! cmd: ${commandBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      return;
    }
    if (_state.connectionState != Sp621eConnectionState.connected) {
      debugPrint('[SP621E] WRITE SKIPPED - not connected!');
      return;
    }

    final hexStr = commandBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    try {
      await _writeCharacteristic!.write(commandBytes, withoutResponse: true);
      debugPrint('[SP621E] WRITE OK: $hexStr');
    } catch (e) {
      debugPrint('[SP621E] WRITE FAILED: $hexStr error: $e');
    }
  }

  // ===== Protocol A: 7E frame format =====
  // Frame: [0x7E, len, cmd, subcmd, data..., 0x00, 0xEF]
  
  Future<void> powerOn() async {
    // Try all known power on commands
    await _writeCommand([0x7E, 0x04, 0x04, 0x01, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
    await _writeCommand([0x7E, 0x00, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0xEF]);
    await _writeCommand([0xCC, 0x23, 0x33]);
    _updateState(_state.copyWith(isOn: true));
  }

  Future<void> powerOff() async {
    await _writeCommand([0x7E, 0x04, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
    await _writeCommand([0x7E, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0xEF]);
    await _writeCommand([0xCC, 0x24, 0x33]);
    _updateState(_state.copyWith(isOn: false));
  }

  Future<void> setBrightness(int brightness) async {
    final clamped = brightness.clamp(0, 255);
    // 7E frame brightness: 7E 04 01 brightness 00 00 FF 00 EF
    await _writeCommand([0x7E, 0x04, 0x01, clamped, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
    await _writeCommand([0x7E, 0x00, 0x01, clamped, 0x00, 0x00, 0x00, 0x00, 0xEF]);
    _updateState(_state.copyWith(brightness: clamped));
  }

  Future<void> setColor(int r, int g, int b) async {
    final rc = r.clamp(0, 255);
    final gc = g.clamp(0, 255);
    final bc = b.clamp(0, 255);
    // Protocol A: 7E 07 05 03 RR GG BB 00 EF
    await _writeCommand([0x7E, 0x07, 0x05, 0x03, rc, gc, bc, 0x00, 0xEF]);
    // Protocol C: 7E 00 05 03 RR GG BB 00 EF
    await _writeCommand([0x7E, 0x00, 0x05, 0x03, rc, gc, bc, 0x00, 0xEF]);
    // Protocol B: 56 RR GG BB 00 F0 AA
    await _writeCommand([0x56, rc, gc, bc, 0x00, 0xF0, 0xAA]);
    _updateState(_state.copyWith(r: rc, g: gc, b: bc));
  }

  Future<void> setEffect(int effect) async {
    // 7E frame effect: 7E 05 03 effect speed 00 FF 00 EF
    await _writeCommand([0x7E, 0x05, 0x03, effect, 0x03, 0x00, 0xFF, 0x00, 0xEF]);
    await _writeCommand([0x7E, 0x00, 0x03, effect, 0x03, 0x00, 0x00, 0x00, 0xEF]);
    _updateState(_state.copyWith(effect: effect));
  }

  Future<void> setEffectSpeed(int speed) async {
    final clamped = speed.clamp(1, 10);
    await _writeCommand([0x7E, 0x04, 0x02, clamped, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
    await _writeCommand([0x7E, 0x00, 0x02, clamped, 0x00, 0x00, 0x00, 0x00, 0xEF]);
    _updateState(_state.copyWith(effectSpeed: clamped));
  }

  Future<void> requestState() async {
    await _writeCommand([0x7E, 0x04, 0x10, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
  }

  Timer? _stormTimer;
  final _random = math.Random();
  LightningScheduler? _lightningScheduler;
  final LightningGenerator _lightningGenerator = LightningGenerator();

  Future<void> _initLightningScheduler() async {
    _lightningScheduler ??= LightningScheduler(
      writeColor: (r, g, b) => _fastSetColor(r, g, b),
      playThunder: (delayMs) {
        // Find a way to play audio. Wait, triggerThunder doesn't have the player here?
        // We will pass the player into triggerThunder, and the scheduler will use a lambda.
      },
    );
  }

  Future<void> flashWhite(int brightness) async {
    final clamped = brightness.clamp(0, 255);
    await setBrightness(clamped);
    await Future.delayed(const Duration(milliseconds: 20));
    await setColor(255, 255, 255);
  }

  Future<void> restoreBackground() async {
    if (!_state.isOn) {
      await powerOff();
      return;
    }
    await setBrightness(_state.brightness);
    await Future.delayed(const Duration(milliseconds: 20));
    if (_state.effect == 0) {
      await setColor(_state.r, _state.g, _state.b);
    } else {
      await setEffect(_state.effect);
    }
  }

  Future<void> setStaticMode() async {
    // 7E 04 04 01 00 00 FF 00 EF forces the controller into static color mode
    await _writeCommand([0x7E, 0x04, 0x04, 0x01, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
  }

  Future<void> _fastSetColor(int r, int g, int b) async {
    await _writeCommand([0x7E, 0x07, 0x05, 0x03, r, g, b, 0x00, 0xEF]);
    // CRITICAL: Prevent packet merging
    await Future.delayed(const Duration(milliseconds: 40));
  }

  Future<void> triggerThunder(ThunderPlayer thunderPlayer, {LightningProfile? profile}) async {
    final prof = profile ?? LightningProfile.normal;
    
    // Generate the deterministic (or random seeded) sequence
    final sequence = _lightningGenerator.generate(prof);

    // Initialize scheduler with the current audio player
    _lightningScheduler = LightningScheduler(
      writeColor: (r, g, b) => _fastSetColor(r, g, b),
      playThunder: (delayMs) {
        // Use the closest matching distance from ThunderDistance based on ms
        // For simplicity, we just use the raw delay in ThunderPlayer by adding a playWithRawDelay method
        // Or we just map the generated delay to a ThunderDistance roughly.
        ThunderDistance dist;
        if (delayMs.inMilliseconds < 600) dist = ThunderDistance.close;
        else if (delayMs.inMilliseconds < 1500) dist = ThunderDistance.mid;
        else dist = ThunderDistance.far;
        
        thunderPlayer.playAfter(dist, delayMs);
      },
    );

    // Force static mode before strike
    await setStaticMode();
    await Future.delayed(const Duration(milliseconds: 50));

    // Execute with try/finally to restore background
    final originalR = _state.r;
    final originalG = _state.g;
    final originalB = _state.b;
    final originalEffect = _state.effect;
    
    try {
      await _lightningScheduler!.execute(sequence);
    } finally {
      // Return to background
      await restoreBackground();
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
    _lightningScheduler?.cancel();
    _scanSub?.cancel();
    _connectionSub?.cancel();
    _stormTimer?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }
}
