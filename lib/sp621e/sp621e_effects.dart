/// The SP621E's built-in effect table.
///
/// These identifiers are what an `A0 63 01 <id>` frame selects. This is the RGB
/// (three-colour, no microphone) variant of the table, which is the one an
/// SP621E reports — the sound-reactive entries its RGBW siblings expose are
/// absent because this controller has no microphone.
library;

/// One entry in the controller's effect table.
class Sp621eEffect {
  const Sp621eEffect(this.id, this.name);

  final int id;
  final String name;

  /// Every effect except [Sp621eEffects.solid] animates, and only animating
  /// effects do anything with `effectSpeed` and `effectLength` — the solid
  /// colour ignores both.
  bool get isDynamic => id != Sp621eEffects.solid;

  /// The controller accepts an arbitrary RGB value only while a colourable
  /// effect is selected. On an SP621E that is [Sp621eEffects.solid] alone;
  /// every other effect has its colours baked into the effect ID.
  bool get isColorable => id == Sp621eEffects.solid;

  @override
  String toString() => '$name (0x${id.toRadixString(16).toUpperCase().padLeft(2, '0')})';
}

class Sp621eEffects {
  Sp621eEffects._();

  /// Whole strip, one RGB colour. The only effect that honours an RGB frame.
  static const int solid = 0xBE;

  /// A white block that travels the strip. Its size is set by the effect
  /// length and its pace by the effect speed, which together are as close as an
  /// SP621E gets to lighting a chosen range of pixels.
  static const int whiteSegmentSpin = 0x8D;

  /// A white head with a fading tail — a sharper, more bolt-like sweep than
  /// [whiteSegmentSpin].
  static const int whiteComet = 0x11;

  /// A white streak that falls and repeats. Reads well as a restrike.
  static const int whiteMeteor = 0x18;

  /// Full-width white travelling wave — the broadest of the white sweeps.
  static const int whiteWave = 0x34;

  static const Map<int, Sp621eEffect> all = {
    0x01: Sp621eEffect(0x01, 'Rainbow'),
    0x02: Sp621eEffect(0x02, 'Rainbow Meteor'),
    0x03: Sp621eEffect(0x03, 'Rainbow Stars'),
    0x04: Sp621eEffect(0x04, 'Rainbow Spin'),
    0x05: Sp621eEffect(0x05, 'Red/Yellow Fire'),
    0x06: Sp621eEffect(0x06, 'Red/Purple Fire'),
    0x07: Sp621eEffect(0x07, 'Green/Yellow Fire'),
    0x08: Sp621eEffect(0x08, 'Green/Cyan Fire'),
    0x09: Sp621eEffect(0x09, 'Blue/Purple Fire'),
    0x0A: Sp621eEffect(0x0A, 'Blue/Cyan Fire'),
    0x0B: Sp621eEffect(0x0B, 'Red Comet'),
    0x0C: Sp621eEffect(0x0C, 'Green Comet'),
    0x0D: Sp621eEffect(0x0D, 'Blue Comet'),
    0x0E: Sp621eEffect(0x0E, 'Yellow Comet'),
    0x0F: Sp621eEffect(0x0F, 'Cyan Comet'),
    0x10: Sp621eEffect(0x10, 'Purple Comet'),
    0x11: Sp621eEffect(0x11, 'White Comet'),
    0x12: Sp621eEffect(0x12, 'Red Meteor'),
    0x13: Sp621eEffect(0x13, 'Green Meteor'),
    0x14: Sp621eEffect(0x14, 'Blue Meteor'),
    0x15: Sp621eEffect(0x15, 'Yellow Meteor'),
    0x16: Sp621eEffect(0x16, 'Cyan Meteor'),
    0x17: Sp621eEffect(0x17, 'Purple Meteor'),
    0x18: Sp621eEffect(0x18, 'White Meteor'),
    0x19: Sp621eEffect(0x19, 'Red/Green Gradual Snake'),
    0x1A: Sp621eEffect(0x1A, 'Red/Blue Gradual Snake'),
    0x1B: Sp621eEffect(0x1B, 'Red/Yellow Gradual Snake'),
    0x1C: Sp621eEffect(0x1C, 'Red/Cyan Gradual Snake'),
    0x1D: Sp621eEffect(0x1D, 'Red/Purple Gradual Snake'),
    0x1E: Sp621eEffect(0x1E, 'Red/White Gradual Snake'),
    0x1F: Sp621eEffect(0x1F, 'Green/Blue Gradual Snake'),
    0x20: Sp621eEffect(0x20, 'Green/Yellow Gradual Snake'),
    0x21: Sp621eEffect(0x21, 'Green/Cyan Gradual Snake'),
    0x22: Sp621eEffect(0x22, 'Green/Purple Gradual Snake'),
    0x23: Sp621eEffect(0x23, 'Green/White Gradual Snake'),
    0x24: Sp621eEffect(0x24, 'Blue/Yellow Gradual Snake'),
    0x25: Sp621eEffect(0x25, 'Blue/Cyan Gradual Snake'),
    0x26: Sp621eEffect(0x26, 'Blue/Purple Gradual Snake'),
    0x27: Sp621eEffect(0x27, 'Blue/White Gradual Snake'),
    0x28: Sp621eEffect(0x28, 'Yellow/Cyan Gradual Snake'),
    0x29: Sp621eEffect(0x29, 'Yellow/Purple Gradual Snake'),
    0x2A: Sp621eEffect(0x2A, 'Yellow/White Gradual Snake'),
    0x2B: Sp621eEffect(0x2B, 'Cyan/Purple Gradual Snake'),
    0x2C: Sp621eEffect(0x2C, 'Cyan/White Gradual Snake'),
    0x2D: Sp621eEffect(0x2D, 'Purple/White Gradual Snake'),
    0x2E: Sp621eEffect(0x2E, 'Red Wave'),
    0x2F: Sp621eEffect(0x2F, 'Green Wave'),
    0x30: Sp621eEffect(0x30, 'Blue Wave'),
    0x31: Sp621eEffect(0x31, 'Yellow Wave'),
    0x32: Sp621eEffect(0x32, 'Cyan Wave'),
    0x33: Sp621eEffect(0x33, 'Purple Wave'),
    0x34: Sp621eEffect(0x34, 'White Wave'),
    0x35: Sp621eEffect(0x35, 'Red/Green Wave'),
    0x36: Sp621eEffect(0x36, 'Red/Blue Wave'),
    0x37: Sp621eEffect(0x37, 'Red/Yellow Wave'),
    0x38: Sp621eEffect(0x38, 'Red/Cyan Wave'),
    0x39: Sp621eEffect(0x39, 'Red/Purple Wave'),
    0x3A: Sp621eEffect(0x3A, 'Red/White Wave'),
    0x3B: Sp621eEffect(0x3B, 'Green/Blue Wave'),
    0x3C: Sp621eEffect(0x3C, 'Green/Yellow Wave'),
    0x3D: Sp621eEffect(0x3D, 'Green/Cyan Wave'),
    0x3E: Sp621eEffect(0x3E, 'Green/Purple Wave'),
    0x3F: Sp621eEffect(0x3F, 'Green/White Wave'),
    0x40: Sp621eEffect(0x40, 'Blue/Yellow Wave'),
    0x41: Sp621eEffect(0x41, 'Blue/Cyan Wave'),
    0x42: Sp621eEffect(0x42, 'Blue/Purple Wave'),
    0x43: Sp621eEffect(0x43, 'Blue/White Wave'),
    0x44: Sp621eEffect(0x44, 'Yellow/Cyan Wave'),
    0x45: Sp621eEffect(0x45, 'Yellow/Purple Wave'),
    0x46: Sp621eEffect(0x46, 'Yellow/White Wave'),
    0x47: Sp621eEffect(0x47, 'Cyan/Purple Wave'),
    0x48: Sp621eEffect(0x48, 'Cyan/White Wave'),
    0x49: Sp621eEffect(0x49, 'Purple/White Wave'),
    0x4A: Sp621eEffect(0x4A, 'Red Stars'),
    0x4B: Sp621eEffect(0x4B, 'Green Stars'),
    0x4C: Sp621eEffect(0x4C, 'Blue Stars'),
    0x4D: Sp621eEffect(0x4D, 'Yellow Stars'),
    0x4E: Sp621eEffect(0x4E, 'Cyan Stars'),
    0x4F: Sp621eEffect(0x4F, 'Purple Stars'),
    0x50: Sp621eEffect(0x50, 'White Stars'),
    0x51: Sp621eEffect(0x51, 'Red Background Stars'),
    0x52: Sp621eEffect(0x52, 'Green Background Stars'),
    0x53: Sp621eEffect(0x53, 'Blue Background Stars'),
    0x54: Sp621eEffect(0x54, 'Yellow Background Stars'),
    0x55: Sp621eEffect(0x55, 'Cyan Background Stars'),
    0x56: Sp621eEffect(0x56, 'Purple Background Stars'),
    0x57: Sp621eEffect(0x57, 'Red/White Background Stars'),
    0x58: Sp621eEffect(0x58, 'Green/White Background Stars'),
    0x59: Sp621eEffect(0x59, 'Blue/White Background Stars'),
    0x5A: Sp621eEffect(0x5A, 'Yellow/White Background Stars'),
    0x5B: Sp621eEffect(0x5B, 'Cyan/White Background Stars'),
    0x5C: Sp621eEffect(0x5C, 'Purple/White Background Stars'),
    0x5D: Sp621eEffect(0x5D, 'White/White Background Stars'),
    0x5E: Sp621eEffect(0x5E, 'Red Breath'),
    0x5F: Sp621eEffect(0x5F, 'Green Breath'),
    0x60: Sp621eEffect(0x60, 'Blue Breath'),
    0x61: Sp621eEffect(0x61, 'Yellow Breath'),
    0x62: Sp621eEffect(0x62, 'Cyan Breath'),
    0x63: Sp621eEffect(0x63, 'Purple Breath'),
    0x64: Sp621eEffect(0x64, 'White Breath'),
    0x65: Sp621eEffect(0x65, 'Red Stacking'),
    0x66: Sp621eEffect(0x66, 'Green Stacking'),
    0x67: Sp621eEffect(0x67, 'Blue Stacking'),
    0x68: Sp621eEffect(0x68, 'Yellow Stacking'),
    0x69: Sp621eEffect(0x69, 'Cyan Stacking'),
    0x6A: Sp621eEffect(0x6A, 'Purple Stacking'),
    0x6B: Sp621eEffect(0x6B, 'White Stacking'),
    0x6C: Sp621eEffect(0x6C, 'Full Color Stack'),
    0x6D: Sp621eEffect(0x6D, 'Red to Green Stack'),
    0x6E: Sp621eEffect(0x6E, 'Green to Blue Stack'),
    0x6F: Sp621eEffect(0x6F, 'Blue to Yellow Stack'),
    0x70: Sp621eEffect(0x70, 'Yellow to Cyan Stack'),
    0x71: Sp621eEffect(0x71, 'Cyan to Purple Stack'),
    0x72: Sp621eEffect(0x72, 'Purple to White Stack'),
    0x73: Sp621eEffect(0x73, 'Red/Blue/White Snake'),
    0x74: Sp621eEffect(0x74, 'Green/Yellow/White Snake'),
    0x75: Sp621eEffect(0x75, 'Red/Green/White Snake'),
    0x76: Sp621eEffect(0x76, 'Red/Yellow Snake'),
    0x77: Sp621eEffect(0x77, 'Red/White Snake'),
    0x78: Sp621eEffect(0x78, 'Green/White Snake'),
    0x79: Sp621eEffect(0x79, 'Red Comet Spin'),
    0x7A: Sp621eEffect(0x7A, 'Green Comet Spin'),
    0x7B: Sp621eEffect(0x7B, 'Blue Comet Spin'),
    0x7C: Sp621eEffect(0x7C, 'Yellow Comet Spin'),
    0x7D: Sp621eEffect(0x7D, 'Cyan Comet Spin'),
    0x7E: Sp621eEffect(0x7E, 'Purple Comet Spin'),
    0x7F: Sp621eEffect(0x7F, 'White Comet Spin'),
    0x80: Sp621eEffect(0x80, 'Red Dot Spin'),
    0x81: Sp621eEffect(0x81, 'Green Dot Spin'),
    0x82: Sp621eEffect(0x82, 'Blue Dot Spin'),
    0x83: Sp621eEffect(0x83, 'Yellow Dot Spin'),
    0x84: Sp621eEffect(0x84, 'Cyan Dot Spin'),
    0x85: Sp621eEffect(0x85, 'Purple Dot Spin'),
    0x86: Sp621eEffect(0x86, 'White Dot Spin'),
    0x87: Sp621eEffect(0x87, 'Red Segment Spin'),
    0x88: Sp621eEffect(0x88, 'Green Segment Spin'),
    0x89: Sp621eEffect(0x89, 'Blue Segment Spin'),
    0x8A: Sp621eEffect(0x8A, 'Yellow Segment Spin'),
    0x8B: Sp621eEffect(0x8B, 'Cyan Segment Spin'),
    0x8C: Sp621eEffect(0x8C, 'Purple Segment Spin'),
    0x8D: Sp621eEffect(0x8D, 'White Segment Spin'),
    0x8E: Sp621eEffect(0x8E, 'Gradient'),
    0xBE: Sp621eEffect(0xBE, 'Solid Color'),
  };

  static Sp621eEffect? byId(int id) => all[id];

  static List<Sp621eEffect> get sorted =>
      all.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  /// The white sweeps, in the order they read from softest to sharpest. These
  /// are the effects the lightning engine draws its moving batches from.
  static const List<int> whiteSweeps = [
    whiteWave,
    whiteSegmentSpin,
    whiteComet,
    whiteMeteor,
  ];
}
