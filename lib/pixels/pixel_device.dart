import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../led_device.dart';
import 'ddp.dart';
import 'lightning_renderer.dart';

/// An ESP32 running the pixel receiver, driven over WiFi.
///
/// Sits alongside the BLE controllers as another [LedDevice] so the rest of the
/// app does not care which it is talking to — but it is not really the same
/// kind of thing. A BLE controller is asked to run one of its own effects; this
/// one is handed finished pixels. Everything the SP621E could not do follows
/// from that difference.
///
/// UDP is the right transport here despite being unreliable: a lost frame is
/// gone in sixteen milliseconds and the next one corrects it, whereas waiting
/// for an acknowledgement would reintroduce exactly the latency this was built
/// to escape.
class PixelDevice extends ChangeNotifier implements LedDevice {
  PixelDevice({
    required this.host,
    required this.pixelCount,
    this.port = Ddp.port,
  }) : _renderer = LightningRenderer(pixelCount: pixelCount);

  /// Address of the ESP32, as printed on its serial console at boot.
  final String host;
  final int port;
  final int pixelCount;

  final LightningRenderer _renderer;

  RawDatagramSocket? _socket;
  InternetAddress? _target;
  int _sequence = 0;

  bool _connected = false;

  @override
  bool get isConnected => _connected;

  /// Per-pixel control is the entire point of this device.
  @override
  bool get supportsSegments => true;

  @override
  String get label => 'ESP32 $host';

  @override
  String? get deviceId => '$host:$port';

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

  /// Nothing is cached, so there is nothing to forget: every frame is sent in
  /// full regardless of what the last one held.
  @override
  void invalidateShadow() {}

  /// A frame goes out in well under a millisecond, so the planner should not
  /// pace itself as though writes were expensive.
  @override
  int get measuredWriteMs => 2;

  /// Opens the socket. There is no handshake — UDP has no connection — so this
  /// only fails if the address itself cannot be resolved.
  Future<bool> open() async {
    try {
      _target = (await InternetAddress.lookup(host)).first;
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _connected = true;
    } catch (e) {
      debugPrint('[Pixels] cannot reach $host: $e');
      _connected = false;
    }
    notifyListeners();
    return _connected;
  }

  /// Present so a [PixelDevice] satisfies [LedDevice]. This device is addressed
  /// by hostname, not by a Bluetooth handle, so the argument is ignored.
  @override
  Future<void> connect(BluetoothDevice device) => open().then((_) {});

  @override
  Future<void> disconnect() async {
    _socket?.close();
    _socket = null;
    _connected = false;
    notifyListeners();
  }

  /// Sends one rendered frame.
  void sendFrame(Uint8List rgb) {
    final socket = _socket;
    final target = _target;
    if (socket == null || target == null || !_connected) return;

    _sequence++;

    for (final packet in Ddp.framePackets(rgb, sequence: _sequence)) {
      try {
        socket.send(packet, target, port);
        _writesSent++;
      } catch (e) {
        debugPrint('[Pixels] send failed: $e');
      }
    }
  }

  /// Plays a strike out at [fps], rendering every frame.
  ///
  /// This is where the difference shows: rather than a handful of brightness
  /// writes, the whole flash is drawn frame by frame, so the decay is a curve
  /// and the bolt is a shape.
  Future<void> playStrike(
    List<Stroke> strokes, {
    int fps = 60,
    double rumble = 0,
    double glowLevel = 0.10,
  }) async {
    if (strokes.isEmpty) return;

    final frameGap = Duration(microseconds: 1000000 ~/ fps);

    var last = Duration.zero;
    for (final stroke in strokes) {
      if (stroke.endsAt > last) last = stroke.endsAt;
    }

    final clock = Stopwatch()..start();

    while (clock.elapsed <= last) {
      sendFrame(_renderer.frame(
        at: clock.elapsed,
        strokes: strokes,
        rumble: rumble,
        glowLevel: glowLevel,
      ));
      await Future<void>.delayed(frameGap);
    }

    // Settle back to the standing glow.
    sendFrame(_renderer.frame(
      at: last + const Duration(seconds: 1),
      strokes: strokes,
      rumble: rumble,
      glowLevel: glowLevel,
    ));
  }

  // -------------------------------------------------------------------
  // LedDevice surface
  //
  // These exist so a pixel device can stand in for a BLE one. They paint whole
  // frames, since that is the only thing this transport sends.
  // -------------------------------------------------------------------

  double _glowLevel = 0.10;

  @override
  Future<void> setPower(bool on) async {
    _glowLevel = on ? _glowLevel : 0;
    sendFrame(_renderer.frame(
      at: Duration.zero,
      strokes: const [],
      glowLevel: on ? _glowLevel : 0,
    ));
  }

  @override
  Future<void> setBrightness(int level) async {
    _glowLevel = (level.clamp(0, 255)) / 255;
    sendFrame(_renderer.frame(
      at: Duration.zero,
      strokes: const [],
      glowLevel: _glowLevel,
    ));
  }

  @override
  Future<void> setColor(int r, int g, int b, {int? level}) async {
    final renderer = LightningRenderer(
      pixelCount: pixelCount,
      glow: PixelColor(r, g, b),
    );
    _glowLevel = ((level ?? 255).clamp(0, 255)) / 255;
    sendFrame(renderer.frame(
      at: Duration.zero,
      strokes: const [],
      glowLevel: _glowLevel,
    ));
  }

  /// Lights a range of pixels directly, which on this device needs no sweep,
  /// no dwell and no darkness to hide travel in.
  @override
  Future<void> setSegment({
    required int effect,
    required int speed,
    required int length,
    required int brightness,
  }) async {
    sendFrame(_renderer.frame(
      at: Duration.zero,
      glowLevel: _glowLevel,
      strokes: [
        Stroke(
          startPixel: 0,
          endPixel: length.clamp(1, pixelCount) - 1,
          at: Duration.zero,
          peak: brightness / 255,
          decay: const Duration(seconds: 10),
        ),
      ],
    ));
  }

  @override
  Future<void> flush() async {
    // Datagrams leave immediately; there is no queue to drain.
  }

  @override
  void dispose() {
    _socket?.close();
    super.dispose();
  }
}
