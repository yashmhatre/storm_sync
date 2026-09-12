/// Wire format for BanlanX "v2" controllers, which is what an SP621E speaks.
///
/// Every command is `A0 <cmd> <payload length> <payload…>` written to
/// characteristic FFE1 on service FFE0. The device pushes unsolicited status
/// back on that same characteristic, framed by [Sp621eStatus.parse].
///
/// The byte assignments here are transcribed from the UniLED Home Assistant
/// integration's `banlanx2.py`, which registers SP621E as
/// `BanlanX2(id: 0x621E, colors: 3, intmic: false)`.
library;

/// Builders for outbound frames. Pure functions — nothing here touches BLE, so
/// every frame is verifiable in a unit test.
class BanlanX2 {
  BanlanX2._();

  static const int frameHeader = 0xA0;

  /// Service and characteristic an SP621E exposes. The write characteristic
  /// doubles as the notify characteristic; there is no separate read handle.
  static const String serviceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String writeUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';

  /// BanlanX's Bluetooth SIG company identifier, 0x5053 — "SP" once the
  /// little-endian advertisement bytes are read in order.
  static const int manufacturerId = 20563;

  /// First manufacturer-data byte an SP621E advertises. Other SPxxxE models in
  /// the same protocol family use different values, so this is what separates
  /// a 621E from its siblings.
  static const List<int> sp621eSignature = [0x0D, 0x16];

  /// Every model known to speak this exact frame format, keyed by the first
  /// byte of its manufacturer data.
  ///
  /// They differ in how many colours they drive and whether they have a
  /// microphone, but the commands this app sends are identical across all of
  /// them, so any of these can be driven and mixed in one fleet.
  ///
  /// A controller that is not in this map may still be an SPxxxE — the family
  /// spans several incompatible protocols — but it will not understand these
  /// frames.
  static const Map<int, String> knownModels = {
    0x04: 'SP611E',
    0x10: 'SP611E',
    0x11: 'SP611E',
    0x12: 'SP611E',
    0x13: 'SP611E',
    0x14: 'SP611E',
    0x15: 'SP611E',
    0x17: 'SP617E',
    0x1B: 'SP620E',
    0x0D: 'SP621E',
    0x16: 'SP621E',
  };

  /// Names the model behind an advertisement, or null when the frame format is
  /// not one this app speaks.
  static String? modelFor(List<int>? manufacturerData) {
    if (manufacturerData == null || manufacturerData.isEmpty) return null;
    return knownModels[manufacturerData.first];
  }

  /// The wire order the controller drives the strip in, as index 0-5.
  ///
  /// These are the permutations of R, G and B in the order the controller
  /// numbers them. Picking the wrong one swaps colour channels, which turns a
  /// blue-white strike into something that looks nothing like lightning, so it
  /// is worth getting right before judging any colour.
  static const List<String> chipOrders = [
    'RGB',
    'RBG',
    'GRB',
    'GBR',
    'BRG',
    'BGR',
  ];

  static const int maxEffectSpeed = 10;
  static const int maxEffectLength = 150;
  static const int maxSensitivity = 16;

  static List<int> _frame(int command, List<int> payload) {
    return [frameHeader, command, payload.length, ...payload];
  }

  /// Ask the controller to report its full state. It answers with a status
  /// notification on FFE1 — see [Sp621eStatus.parse].
  static List<int> queryState() => _frame(0x70, const []);

  static List<int> power(bool on) => _frame(0x62, [on ? 0x01 : 0x00]);

  static List<int> effect(int id) => _frame(0x63, [id & 0xFF]);

  static List<int> chipOrder(int order) => _frame(0x64, [order & 0xFF]);

  static List<int> brightness(int level) =>
      _frame(0x66, [level.clamp(0, 255).toInt()]);

  static List<int> effectSpeed(int speed) =>
      _frame(0x67, [speed.clamp(1, maxEffectSpeed).toInt()]);

  /// Size of the moving element in a dynamic effect, in pixels.
  static List<int> effectLength(int length) =>
      _frame(0x68, [length.clamp(1, maxEffectLength).toInt()]);

  /// Colour *and* level travel in one frame. The controller only honours this
  /// while a colourable effect is active — on an SP621E that means
  /// [Sp621eEffects.solid] and nothing else.
  static List<int> rgb(int r, int g, int b, int level) => _frame(0x69, [
        r.clamp(0, 255).toInt(),
        g.clamp(0, 255).toInt(),
        b.clamp(0, 255).toInt(),
        level.clamp(0, 255).toInt(),
      ]);

  static List<int> lightMode(int mode) => _frame(0x6A, [mode & 0xFF]);

  static List<int> sensitivity(int gain) =>
      _frame(0x6B, [gain.clamp(1, maxSensitivity).toInt()]);

  static List<int> audioInput(int input) => _frame(0x6C, [input & 0xFF]);

  /// Only meaningful on the RGBW models in this family. An SP621E is RGB, so
  /// this is here for completeness rather than use.
  static List<int> whiteLevel(int level) =>
      _frame(0x76, [level.clamp(0, 255).toInt(), 0x00]);

  static String hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}

/// Whether the controller is running one chosen effect or cycling through a
/// category on its own.
enum Sp621eLightMode {
  single(0x00, 'Single effect'),
  cycleDynamic(0x01, 'Cycle dynamic effects'),
  cycleSound(0x02, 'Cycle sound effects');

  const Sp621eLightMode(this.id, this.label);

  final int id;
  final String label;

  static Sp621eLightMode fromId(int id) => values.firstWhere(
        (m) => m.id == id,
        orElse: () => Sp621eLightMode.single,
      );
}

/// A decoded status notification.
///
/// The controller sends these unprompted on every change, so this is the only
/// honest source of truth about what the hardware is actually doing.
class Sp621eStatus {
  const Sp621eStatus({
    required this.isOn,
    required this.lightMode,
    required this.effect,
    required this.chipOrder,
    required this.brightness,
    required this.speed,
    required this.length,
    required this.r,
    required this.g,
    required this.b,
  });

  final bool isOn;
  final Sp621eLightMode lightMode;
  final int effect;
  final int chipOrder;
  final int brightness;
  final int speed;
  final int length;
  final int r;
  final int g;
  final int b;

  /// Notifications are framed `53 43 <packet#> <total length> <payload length>`
  /// followed by the payload. A long status spans several packets; this returns
  /// null for a fragment that does not yet carry a full payload, and the caller
  /// is expected to feed it the reassembled bytes.
  static const int statusFlag1 = 0x53; // 'S'
  static const int statusFlag2 = 0x43; // 'C'
  static const int headerLength = 5;

  static bool isStatusFrame(List<int> data) =>
      data.length > headerLength &&
      data[0] == statusFlag1 &&
      data[1] == statusFlag2;

  /// Decodes a reassembled payload — that is, a frame with its 5-byte header
  /// already removed, or a headerless payload the controller sent whole.
  ///
  /// Returns null rather than throwing on a short or malformed payload, since
  /// a dropped BLE packet is an expected event, not a programming error.
  static Sp621eStatus? parse(List<int> data) {
    var payload = data;
    if (isStatusFrame(payload)) {
      payload = payload.sublist(headerLength);
    }

    // Bytes 0-11 carry everything this app reads; the tail is timers and
    // per-model extras that an SP621E does not use.
    if (payload.length < 12) return null;

    return Sp621eStatus(
      isOn: payload[0] == 0x01,
      lightMode: Sp621eLightMode.fromId(payload[1]),
      effect: payload[2],
      chipOrder: payload[3],
      brightness: payload[4],
      speed: payload[5],
      length: payload[6],
      r: payload[7],
      g: payload[8],
      b: payload[9],
    );
  }

  @override
  String toString() => 'Sp621eStatus(on: $isOn, mode: ${lightMode.name}, '
      'effect: 0x${effect.toRadixString(16)}, bri: $brightness, '
      'speed: $speed, len: $length, rgb: ($r, $g, $b))';
}
