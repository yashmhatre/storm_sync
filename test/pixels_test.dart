import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:storm_sync/pixels/ddp.dart';
import 'package:storm_sync/pixels/lightning_renderer.dart';
import 'package:storm_sync/thunder/bolt_segments.dart';

void main() {
  group('DDP packets', () {
    test('a small frame is one pushed packet', () {
      final rgb = Uint8List(30 * 3);
      final packets = Ddp.framePackets(rgb, sequence: 0);

      expect(packets, hasLength(1));
      final p = packets.single;

      expect(p[0] & Ddp.flagsVersion1, Ddp.flagsVersion1);
      expect(p[0] & Ddp.flagsPush, Ddp.flagsPush,
          reason: 'the last packet of a frame must ask for display');
      expect(p[2], Ddp.dataTypeRgb24);
      expect(p[3], Ddp.defaultDestination);
      expect(p.length, Ddp.headerLength + 90);
    });

    test('declares its own offset and length', () {
      final rgb = Uint8List(10 * 3);
      final p = Ddp.framePackets(rgb, sequence: 0).single;

      final offset = (p[4] << 24) | (p[5] << 16) | (p[6] << 8) | p[7];
      final length = (p[8] << 8) | p[9];

      expect(offset, 0);
      expect(length, 30);
    });

    test('a long strip splits, and only the last packet pushes', () {
      // 1000 pixels needs three packets at 480 per packet.
      final rgb = Uint8List(1000 * 3);
      final packets = Ddp.framePackets(rgb, sequence: 3);

      expect(packets, hasLength(3));

      for (var i = 0; i < packets.length; i++) {
        final isLast = i == packets.length - 1;
        final pushed = packets[i][0] & Ddp.flagsPush != 0;
        expect(pushed, isLast,
            reason: 'half a frame must not be displayed as a whole one');
      }
    });

    test('split packets carry consecutive offsets covering the frame', () {
      final rgb = Uint8List(1000 * 3);
      final packets = Ddp.framePackets(rgb, sequence: 0);

      var expected = 0;
      for (final p in packets) {
        final offset = (p[4] << 24) | (p[5] << 16) | (p[6] << 8) | p[7];
        final length = (p[8] << 8) | p[9];

        expect(offset, expected);
        expect(p.length, Ddp.headerLength + length);
        expected += length;
      }
      expect(expected, rgb.length);
    });

    test('pixel bytes survive the trip into the packet', () {
      final rgb = Uint8List.fromList([1, 2, 3, 250, 251, 252]);
      final p = Ddp.framePackets(rgb, sequence: 0).single;

      expect(p.sublist(Ddp.headerLength), [1, 2, 3, 250, 251, 252]);
    });

    test('sequence stays inside 1-15, since 0 means unsequenced', () {
      for (var i = 0; i < 40; i++) {
        final p = Ddp.framePackets(Uint8List(3), sequence: i).single;
        expect(p[1], inInclusiveRange(1, 15));
      }
    });

    test('an empty frame sends nothing', () {
      expect(Ddp.framePackets(Uint8List(0), sequence: 0), isEmpty);
    });
  });

  group('rendering', () {
    const renderer = LightningRenderer(pixelCount: 100);

    int brightnessAt(Uint8List frame, int pixel) {
      final at = pixel * 3;
      return frame[at] + frame[at + 1] + frame[at + 2];
    }

    test('with no strokes the whole strip sits at the glow', () {
      final frame = renderer.frame(at: Duration.zero, strokes: const []);

      expect(frame, hasLength(300));
      final first = brightnessAt(frame, 0);
      for (var i = 1; i < 100; i++) {
        expect(brightnessAt(frame, i), first);
      }
    });

    test('a stroke lights its own pixels and leaves the rest glowing', () {
      final frame = renderer.frame(
        at: Duration.zero,
        strokes: [
          const Stroke(
            startPixel: 40,
            endPixel: 60,
            at: Duration.zero,
            peak: 1.0,
            decay: Duration(milliseconds: 50),
          ),
        ],
      );

      // This is the thing the SP621E could never do: bright here, dim there,
      // at the same instant.
      expect(brightnessAt(frame, 50), greaterThan(brightnessAt(frame, 10) * 5));
      expect(brightnessAt(frame, 90), brightnessAt(frame, 10));
    });

    test('the bolt is blue-white, not white or magenta', () {
      final frame = renderer.frame(
        at: Duration.zero,
        strokes: [
          const Stroke(
            startPixel: 10,
            endPixel: 30,
            at: Duration.zero,
            peak: 1.0,
            decay: Duration(milliseconds: 50),
          ),
        ],
      );

      final at = 20 * 3;
      expect(frame[at + 2], greaterThan(frame[at + 1]),
          reason: 'blue above green');
      expect(frame[at + 1], greaterThan(frame[at]), reason: 'green above red');
    });

    test('a stroke decays smoothly rather than switching off', () {
      const stroke = Stroke(
        startPixel: 0,
        endPixel: 10,
        at: Duration.zero,
        peak: 1.0,
        decay: Duration(milliseconds: 50),
      );

      final levels = [
        for (var ms = 0; ms <= 200; ms += 10)
          stroke.levelAt(Duration(milliseconds: ms)),
      ];

      expect(levels.first, 1.0);
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i], lessThan(levels[i - 1]));
      }
      expect(levels.last, lessThan(0.02));
    });

    test('a stroke contributes nothing before it fires', () {
      const stroke = Stroke(
        startPixel: 0,
        endPixel: 10,
        at: Duration(milliseconds: 100),
        peak: 1.0,
        decay: Duration(milliseconds: 50),
      );

      expect(stroke.levelAt(Duration.zero), 0);
      expect(stroke.levelAt(const Duration(milliseconds: 99)), 0);
      expect(stroke.levelAt(const Duration(milliseconds: 100)), 1.0);
    });

    test('rumble lifts the whole strip without lighting a bolt', () {
      final quiet = renderer.frame(at: Duration.zero, strokes: const []);
      final rolling =
          renderer.frame(at: Duration.zero, strokes: const [], rumble: 1.0);

      expect(brightnessAt(rolling, 50), greaterThan(brightnessAt(quiet, 50)));
    });

    test('overlapping strokes take the brighter, never darken each other', () {
      final frame = renderer.frame(
        at: Duration.zero,
        strokes: [
          const Stroke(
            startPixel: 0,
            endPixel: 50,
            at: Duration.zero,
            peak: 0.2,
            decay: Duration(milliseconds: 50),
          ),
          const Stroke(
            startPixel: 20,
            endPixel: 30,
            at: Duration.zero,
            peak: 1.0,
            decay: Duration(milliseconds: 50),
          ),
        ],
      );

      expect(brightnessAt(frame, 25), greaterThan(brightnessAt(frame, 5)));
    });
  });

  group('composing a strike', () {
    const bolts = [
      BoltSegment(id: 'a', name: 'A', startPixel: 10, endPixel: 50),
      BoltSegment(id: 'b', name: 'B', startPixel: 200, endPixel: 244),
    ];

    test('all strokes of a strike land on one bolt shape', () {
      for (var seed = 0; seed < 20; seed++) {
        final strokes = StrikeComposer(random: Random(seed))
            .compose(bolts: bolts, pixelCount: 288);

        expect(strokes, isNotEmpty);
        final first = strokes.first;
        for (final s in strokes) {
          expect(s.startPixel, first.startPixel,
              reason: 'a flash is one channel, not several');
          expect(s.endPixel, first.endPixel);
        }

        final matched = bolts.any((b) =>
            b.startPixel == first.startPixel && b.endPixel == first.endPixel);
        expect(matched, isTrue, reason: 'strokes must sit on a real bolt');
      }
    });

    test('later strokes are dimmer', () {
      final strokes = StrikeComposer(random: Random(4))
          .compose(bolts: bolts, pixelCount: 288);

      for (var i = 1; i < strokes.length; i++) {
        expect(strokes[i].peak, lessThan(strokes[i - 1].peak));
      }
    });

    test('strokes are ordered in time', () {
      final strokes = StrikeComposer(random: Random(6))
          .compose(bolts: bolts, pixelCount: 288);

      for (var i = 1; i < strokes.length; i++) {
        expect(strokes[i].at, greaterThanOrEqualTo(strokes[i - 1].at));
      }
    });

    test('falls back to a random stretch when no bolts are defined', () {
      final strokes = StrikeComposer(random: Random(2))
          .compose(bolts: const [], pixelCount: 288);

      expect(strokes, isNotEmpty);
      final s = strokes.first;
      expect(s.endPixel - s.startPixel, inInclusiveRange(30, 50));
      expect(s.endPixel, lessThanOrEqualTo(288));
    });

    test('different strikes pick different bolts', () {
      final chosen = <int>{};
      for (var seed = 0; seed < 20; seed++) {
        final strokes = StrikeComposer(random: Random(seed))
            .compose(bolts: bolts, pixelCount: 288);
        chosen.add(strokes.first.startPixel);
      }
      expect(chosen.length, 2);
    });
  });
}
