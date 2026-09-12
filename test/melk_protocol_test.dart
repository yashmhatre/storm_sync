import 'package:flutter_test/flutter_test.dart';
import 'package:storm_sync/melk/melk_protocol.dart';

/// The expected bytes are the frames the `elkbledom` integration builds for a
/// MELK controller. Golden values: if one changes, the app has stopped speaking
/// the protocol.
void main() {
  group('frames', () {
    test('every command frame is nine bytes wrapped in 7E…EF', () {
      final frames = <List<int>>[
        Melk.power(true),
        Melk.power(false),
        Melk.rgb(1, 2, 3),
        Melk.brightnessPercent(50),
        Melk.effect(0x80),
        Melk.effectSpeed(40),
        Melk.queryState(),
      ];

      for (final frame in frames) {
        expect(frame, hasLength(9), reason: Melk.hex(frame));
        expect(frame.first, Melk.frameStart);
        expect(frame.last, Melk.frameEnd);
      }
    });

    test('power', () {
      expect(Melk.power(true), [0x7E, 0x04, 0x04, 0xF0, 0x00, 0x01, 0xFF, 0x00, 0xEF]);
      expect(Melk.power(false), [0x7E, 0x04, 0x04, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEF]);
    });

    test('colour', () {
      expect(Melk.rgb(0xFF, 0x80, 0x00),
          [0x7E, 0x00, 0x05, 0x03, 0xFF, 0x80, 0x00, 0x00, 0xEF]);
    });

    test('brightness is a percentage, not a level', () {
      expect(Melk.brightnessPercent(100),
          [0x7E, 0x04, 0x01, 0x64, 0x01, 0xFF, 0xFF, 0x00, 0xEF]);
      expect(Melk.brightnessPercent(0)[3], 0x00);
    });

    test('effect and speed', () {
      expect(Melk.effect(0x25), [0x7E, 0x05, 0x03, 0x25, 0x06, 0xFF, 0xFF, 0x00, 0xEF]);
      expect(Melk.effectSpeed(50)[3], 50);
    });

    test('out-of-range arguments clamp rather than corrupt the frame', () {
      expect(Melk.rgb(300, -5, 999).sublist(4, 7), [0xFF, 0x00, 0xFF]);
      expect(Melk.brightnessPercent(500)[3], 100);
      expect(Melk.brightnessPercent(-20)[3], 0);
      expect(Melk.effectSpeed(999)[3], 100);
    });
  });

  group('level conversion', () {
    test('0-255 maps onto 0-100', () {
      expect(Melk.levelToPercent(0), 0);
      expect(Melk.levelToPercent(255), 100);
      expect(Melk.levelToPercent(128), 50);
    });

    test('brightness() accepts the same 0-255 scale as the rest of the app', () {
      // The two controllers disagree about scale; this is where that is
      // reconciled, so a shared brightness means the same thing on both.
      expect(Melk.brightness(255)[3], 100);
      expect(Melk.brightness(0)[3], 0);
      expect(Melk.brightness(64)[3], 25);
    });

    test('clamps outside the level range', () {
      expect(Melk.levelToPercent(-40), 0);
      expect(Melk.levelToPercent(4000), 100);
    });
  });

  group('identification', () {
    test('recognises the family by name, since they advertise no maker data', () {
      expect(Melk.looksLikeMelk('MELK-OT21   69'), isTrue);
      expect(Melk.looksLikeMelk('ELK-BLEDOM'), isTrue);
      expect(Melk.looksLikeMelk('LEDBLE-12345'), isTrue);
      expect(Melk.looksLikeMelk('melk-oa21'), isTrue);
    });

    test('does not claim unrelated devices', () {
      expect(Melk.looksLikeMelk('SP621E'), isFalse);
      expect(Melk.looksLikeMelk('FireBoltt 156'), isFalse);
      expect(Melk.looksLikeMelk(''), isFalse);
    });
  });

  group('login', () {
    test('is two short frames with no terminator', () {
      expect(Melk.loginSequence, hasLength(2));
      expect(Melk.loginSequence[0], [0x7E, 0x07, 0x83]);
      expect(Melk.loginSequence[1], [0x7E, 0x04, 0x04]);

      for (final frame in Melk.loginSequence) {
        expect(frame.last, isNot(Melk.frameEnd),
            reason: 'login frames are not terminated like command frames');
      }
    });
  });
}
