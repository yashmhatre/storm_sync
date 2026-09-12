/// Wire format for ELK-BLEDOM / MELK controllers, which is what a MELK-OT21
/// speaks.
///
/// Nothing like the BanlanX format the SP621E uses. Frames here are a fixed
/// nine bytes wrapped in `7E … EF`, written to characteristic FFF3, and the
/// controller drives a **plain RGB strip**: there is no pixel addressing, so
/// every command affects the whole run at once.
///
/// Transcribed from the `elkbledom` Home Assistant integration, which covers
/// the ELK-, MELK-, LEDBLE and XROCKER families.
library;

class Melk {
  Melk._();

  static const int frameStart = 0x7E;
  static const int frameEnd = 0xEF;

  static const String serviceUuid = '0000fff0-0000-1000-8000-00805f9b34fb';
  static const String writeUuid = '0000fff3-0000-1000-8000-00805f9b34fb';
  static const String notifyUuid = '0000fff4-0000-1000-8000-00805f9b34fb';

  /// Name prefixes that identify a controller of this family. These devices
  /// advertise no manufacturer data at all, so the name is the only signal.
  static const List<String> namePrefixes = [
    'MELK',
    'ELK-BLE',
    'ELK-BTC',
    'ELK-BULB',
    'ELK-LAMP',
    'LEDBLE',
    'XSL-',
  ];

  static bool looksLikeMelk(String name) {
    final upper = name.toUpperCase();
    return namePrefixes.any(upper.startsWith);
  }

  /// Sent immediately after connecting, before anything else.
  ///
  /// MELK units ignore commands until this pair has gone out. They are short
  /// frames with no terminator, unlike everything that follows.
  static const List<List<int>> loginSequence = [
    [0x7E, 0x07, 0x83],
    [0x7E, 0x04, 0x04],
  ];

  static List<int> power(bool on) => on
      ? [0x7E, 0x04, 0x04, 0xF0, 0x00, 0x01, 0xFF, 0x00, 0xEF]
      : [0x7E, 0x04, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF];

  /// Whole-strip colour. The only spatial control this hardware has is none.
  static List<int> rgb(int r, int g, int b) => [
        0x7E,
        0x00,
        0x05,
        0x03,
        r.clamp(0, 255).toInt(),
        g.clamp(0, 255).toInt(),
        b.clamp(0, 255).toInt(),
        0x00,
        0xEF,
      ];

  /// Brightness, as a **percentage**. This is the trap in this protocol: the
  /// BanlanX side takes 0-255 and this one takes 0-100, so anything shared
  /// between the two has to be converted rather than passed straight through.
  static List<int> brightnessPercent(int percent) => [
        0x7E,
        0x04,
        0x01,
        percent.clamp(0, 100).toInt(),
        0x01,
        0xFF,
        0xFF,
        0x00,
        0xEF,
      ];

  /// Converts an 0-255 level, as used everywhere else in this app, to the
  /// percentage this controller expects.
  static int levelToPercent(int level) =>
      (level.clamp(0, 255) * 100 / 255).round().clamp(0, 100);

  static List<int> brightness(int level) =>
      brightnessPercent(levelToPercent(level));

  static List<int> effect(int id) =>
      [0x7E, 0x05, 0x03, id & 0xFF, 0x06, 0xFF, 0xFF, 0x00, 0xEF];

  static List<int> effectSpeed(int speed) =>
      [0x7E, 0x04, 0x02, speed.clamp(0, 100).toInt(), 0xFF, 0xFF, 0xFF, 0x00, 0xEF];

  static List<int> queryState() =>
      [0x7E, 0x00, 0x01, 0xFA, 0x00, 0x00, 0x00, 0x00, 0xEF];

  static String hex(List<int> bytes) => bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
}
