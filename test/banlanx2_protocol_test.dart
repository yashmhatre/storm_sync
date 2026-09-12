import 'package:flutter_test/flutter_test.dart';
import 'package:storm_sync/sp621e/banlanx2_protocol.dart';
import 'package:storm_sync/sp621e/sp621e_effects.dart';

/// The expected bytes below are the frames UniLED's `banlanx2.py` builds for
/// an SP621E. They are golden values: if one changes, the app has stopped
/// speaking the controller's protocol.
void main() {
  group('outbound frames', () {
    test('every frame is A0, command, payload length, payload', () {
      final frames = <List<int>>[
        BanlanX2.queryState(),
        BanlanX2.power(true),
        BanlanX2.effect(Sp621eEffects.solid),
        BanlanX2.brightness(128),
        BanlanX2.rgb(1, 2, 3, 4),
        BanlanX2.effectSpeed(5),
        BanlanX2.effectLength(48),
      ];

      for (final frame in frames) {
        expect(frame[0], BanlanX2.frameHeader, reason: BanlanX2.hex(frame));
        expect(frame[2], frame.length - 3,
            reason: 'declared length must match payload: ${BanlanX2.hex(frame)}');
      }
    });

    test('state query', () {
      expect(BanlanX2.queryState(), [0xA0, 0x70, 0x00]);
    });

    test('power', () {
      expect(BanlanX2.power(true), [0xA0, 0x62, 0x01, 0x01]);
      expect(BanlanX2.power(false), [0xA0, 0x62, 0x01, 0x00]);
    });

    test('effect selection', () {
      expect(BanlanX2.effect(Sp621eEffects.solid), [0xA0, 0x63, 0x01, 0xBE]);
      expect(BanlanX2.effect(Sp621eEffects.whiteSegmentSpin),
          [0xA0, 0x63, 0x01, 0x8D]);
    });

    test('brightness', () {
      expect(BanlanX2.brightness(0), [0xA0, 0x66, 0x01, 0x00]);
      expect(BanlanX2.brightness(255), [0xA0, 0x66, 0x01, 0xFF]);
    });

    test('rgb carries the level as a fourth byte', () {
      expect(BanlanX2.rgb(0xFF, 0x00, 0x80, 0xC0),
          [0xA0, 0x69, 0x04, 0xFF, 0x00, 0x80, 0xC0]);
    });

    test('speed and length', () {
      expect(BanlanX2.effectSpeed(10), [0xA0, 0x67, 0x01, 0x0A]);
      expect(BanlanX2.effectLength(150), [0xA0, 0x68, 0x01, 0x96]);
    });

    test('light mode', () {
      expect(BanlanX2.lightMode(Sp621eLightMode.single.id),
          [0xA0, 0x6A, 0x01, 0x00]);
    });

    test('out-of-range arguments clamp instead of corrupting the frame', () {
      // A malformed length byte would desynchronise the controller's parser,
      // so clamping matters more than rejecting.
      expect(BanlanX2.brightness(999), [0xA0, 0x66, 0x01, 0xFF]);
      expect(BanlanX2.brightness(-5), [0xA0, 0x66, 0x01, 0x00]);
      expect(BanlanX2.effectSpeed(0), [0xA0, 0x67, 0x01, 0x01]);
      expect(BanlanX2.effectSpeed(99), [0xA0, 0x67, 0x01, 0x0A]);
      expect(BanlanX2.effectLength(0), [0xA0, 0x68, 0x01, 0x01]);
      expect(BanlanX2.effectLength(9999), [0xA0, 0x68, 0x01, 0x96]);
      expect(BanlanX2.rgb(300, -1, 256, 999),
          [0xA0, 0x69, 0x04, 0xFF, 0x00, 0xFF, 0xFF]);
    });
  });

  group('status notifications', () {
    // Captured from a real SP621E, quoted in banlanx2.py:
    //   01 00 0e 02 61 0a 1e ff 00 00 01 10 …
    final sp621ePayload = [
      0x01, 0x00, 0x0E, 0x02, 0x61, 0x0A, 0x1E, //
      0xFF, 0x00, 0x00, 0x01, 0x10,
      0x09, 0x04, 0x0B, 0x14, 0x1A, 0x32, 0x37, 0x50, 0x53, 0x73, 0x00,
    ];

    test('decodes a headerless payload', () {
      final status = Sp621eStatus.parse(sp621ePayload)!;

      expect(status.isOn, isTrue);
      expect(status.lightMode, Sp621eLightMode.single);
      expect(status.effect, 0x0E);
      expect(status.chipOrder, 0x02);
      expect(status.brightness, 0x61);
      expect(status.speed, 0x0A);
      expect(status.length, 0x1E);
      expect([status.r, status.g, status.b], [0xFF, 0x00, 0x00]);
    });

    test('strips the 53 43 framing header when present', () {
      final framed = [
        Sp621eStatus.statusFlag1,
        Sp621eStatus.statusFlag2,
        0x01,
        sp621ePayload.length,
        sp621ePayload.length,
        ...sp621ePayload,
      ];

      expect(Sp621eStatus.isStatusFrame(framed), isTrue);
      expect(Sp621eStatus.parse(framed)!.brightness, 0x61);
    });

    test('a solid-colour status reports effect 0xBE', () {
      // 01 00 be 08 ff 05 4a ff 00 00 …
      final status = Sp621eStatus.parse(
        [0x01, 0x00, 0xBE, 0x08, 0xFF, 0x05, 0x4A, 0xFF, 0x00, 0x00, 0x00, 0x10],
      )!;

      expect(status.effect, Sp621eEffects.solid);
      expect(Sp621eEffects.byId(status.effect)!.isColorable, isTrue);
      expect(status.brightness, 0xFF);
    });

    test('returns null for a truncated payload rather than throwing', () {
      expect(Sp621eStatus.parse([0x01, 0x00, 0xBE]), isNull);
      expect(Sp621eStatus.parse(const []), isNull);
    });
  });

  group('effect table', () {
    test('solid is the only colourable effect', () {
      final colorable =
          Sp621eEffects.all.values.where((e) => e.isColorable).toList();
      expect(colorable.map((e) => e.id), [Sp621eEffects.solid]);
    });

    test('solid is the only static effect', () {
      final static =
          Sp621eEffects.all.values.where((e) => !e.isDynamic).toList();
      expect(static.map((e) => e.id), [Sp621eEffects.solid]);
    });

    test('the white sweeps the lightning engine relies on all exist', () {
      for (final id in Sp621eEffects.whiteSweeps) {
        final effect = Sp621eEffects.byId(id);
        expect(effect, isNotNull, reason: 'missing effect 0x${id.toRadixString(16)}');
        expect(effect!.name.toLowerCase(), contains('white'));
      }
    });
  });
}
