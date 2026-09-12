import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:storm_sync/audio/thunder_player.dart';
import 'package:storm_sync/sp621e/sp621e_effects.dart';
import 'package:storm_sync/audio/thunder_envelope.dart';
import 'package:storm_sync/thunder/bolt_segments.dart';
import 'package:storm_sync/thunder/strike_plan.dart';
import 'package:storm_sync/thunder/strike_planner.dart';
import 'package:storm_sync/thunder/strip_calibration.dart';
import 'package:storm_sync/thunder/thunder_preset.dart';

ThunderPreset _preset({
  double sharpness = 0.5,
  double energy = 0.8,
  int rumbleTailMs = 600,
  double position = 0.5,
  int speed = 5,
  int width = 48,
  bool flood = true,
  ThunderDistance distance = ThunderDistance.mid,
}) {
  return ThunderPreset(
    id: 'test',
    name: 'Test',
    sound: ThunderSound(
      distance: distance,
      sharpness: sharpness,
      energy: energy,
      rumbleTailMs: rumbleTailMs,
    ),
    placement: StrikePlacement(
      position: position,
      widthPixels: width,
      speed: speed,
      floodOnImpact: flood,
    ),
  );
}

void main() {
  // A fixed seed keeps the probabilistic parts of the planner repeatable.
  StrikePlanner planner() => StrikePlanner(random: Random(7));
  const calibration = StripCalibration(traverseMsAtSpeed1: 10000);

  group('placement becomes dwell time', () {
    test('a further position holds the sweep longer', () {
      final near = planner().build(_preset(position: 0.2), calibration);
      final far = planner().build(_preset(position: 0.9), calibration);

      expect(
        far.mainStrokeAt,
        greaterThan(near.mainStrokeAt),
        reason: 'a bolt landing further along the strip needs a longer sweep',
      );
    });

    test('dwell matches the calibration arithmetic', () {
      // At speed 5 a full traverse is 10000 / 5 = 2000ms, so halfway is 1000ms.
      expect(calibration.traverseMs(5), 2000);
      expect(
        calibration.dwellForPosition(0.5, 5),
        const Duration(milliseconds: 1000),
      );
    });

    test('a faster sweep reaches the same position sooner', () {
      final slow = planner().build(_preset(position: 0.8, speed: 2), calibration);
      final fast = planner().build(_preset(position: 0.8, speed: 9), calibration);

      expect(fast.mainStrokeAt, lessThan(slow.mainStrokeAt));
    });

    test('the main sweep carries the requested width and speed', () {
      final plan = planner().build(
        _preset(position: 0.5, width: 33, speed: 7),
        calibration,
      );

      final sweep = plan.steps.whereType<SweepStep>().firstWhere(
            (s) => s.label.startsWith('bolt to'),
          );

      expect(sweep.length, 33);
      expect(sweep.speed, 7);
    });

    test('minimumPlacement reports the floor the write cost imposes', () {
      // Four writes at 40ms each is 160ms, against a 2000ms traverse.
      expect(
        StrikePlanner.minimumPlacement(5, calibration),
        closeTo(0.08, 0.001),
      );
    });
  });

  group('the sound shapes the light', () {
    test('a sharp crack flickers more than a distant roll', () {
      final roll = planner().build(_preset(sharpness: 0.1), calibration);
      final crack = planner().build(_preset(sharpness: 1.0), calibration);

      int pulses(StrikePlan p) => p.steps.whereType<FlickerStep>().length;

      expect(pulses(crack), greaterThan(pulses(roll)));
    });

    test('energy sets the brightness of the main sweep', () {
      final dim = planner().build(_preset(energy: 0.3), calibration);
      final bright = planner().build(_preset(energy: 1.0), calibration);

      int mainBrightness(StrikePlan p) => p.steps
          .whereType<SweepStep>()
          .firstWhere((s) => s.label.startsWith('bolt to'))
          .brightness;

      expect(mainBrightness(dim), lessThan(mainBrightness(bright)));
      expect(mainBrightness(bright), 255);
    });

    test('the rumble tail lengthens the plan', () {
      final short = planner().build(_preset(rumbleTailMs: 0), calibration);
      final long = planner().build(_preset(rumbleTailMs: 2000), calibration);

      expect(long.visualDuration, greaterThan(short.visualDuration));
      expect(
        short.steps.any((s) => s.label == 'rumble tail'),
        isFalse,
        reason: 'no tail was asked for',
      );
    });

    test('thunder delay comes from the chosen sample', () {
      final near = planner().build(
        _preset(distance: ThunderDistance.close),
        calibration,
      );
      final far = planner().build(
        _preset(distance: ThunderDistance.far),
        calibration,
      );

      expect(near.thunderDelay.inMilliseconds,
          ThunderDistance.close.distanceDelayMs);
      expect(far.thunderDelay, greaterThan(near.thunderDelay));
    });

    test('a warmer sound strikes with a warmer white', () {
      const cold = ThunderSound(
        distance: ThunderDistance.close,
        sharpness: 1,
        energy: 1,
        rumbleTailMs: 0,
        warmth: 0,
      );
      const warm = ThunderSound(
        distance: ThunderDistance.far,
        sharpness: 0,
        energy: 1,
        rumbleTailMs: 0,
        warmth: 40,
      );

      final (_, _, coldBlue) = cold.strikeColor;
      final (_, _, warmBlue) = warm.strikeColor;

      expect(warmBlue, lessThan(coldBlue),
          reason: 'warmth is expressed by pulling blue out of the white');
    });

    test('suppressing the flood removes the full-strip steps', () {
      final plan = planner().build(_preset(flood: false), calibration);

      expect(
        plan.steps.any((s) => s.label == 'return stroke'),
        isFalse,
      );
    });
  });

  group('plans stay inside what the link can carry', () {
    test('steps are never scheduled closer than their write cost allows', () {
      for (final sharpness in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final plan = planner().build(_preset(sharpness: sharpness), calibration);

        for (var i = 1; i < plan.steps.length; i++) {
          final gap = plan.steps[i].at - plan.steps[i - 1].at;
          final need =
              plan.steps[i - 1].writeCost * StrikePlanner.defaultWriteCostMs;

          expect(
            gap.inMilliseconds,
            greaterThanOrEqualTo(min(need, StrikePlanner.minStepGapMs)),
            reason: 'step ${plan.steps[i].label} crowds the one before it',
          );
        }
      }
    });

    test('steps are ordered in time', () {
      final plan = planner().build(_preset(), calibration);
      for (var i = 1; i < plan.steps.length; i++) {
        expect(plan.steps[i].at, greaterThanOrEqualTo(plan.steps[i - 1].at));
      }
    });

    test('every plan ends dark, so the strip cannot be left lit', () {
      for (final preset in ThunderPreset.defaults()) {
        final plan = planner().build(preset, calibration);
        expect(plan.steps.last, isA<DarkStep>(),
            reason: '${preset.name} does not end dark');
      }
    });

    test('the shipped presets do not exceed a sustainable write rate', () {
      for (final preset in ThunderPreset.defaults()) {
        final plan = planner().build(preset, calibration);
        expect(
          plan.writesPerSecond,
          lessThan(25),
          reason: '${preset.name} asks for more traffic than BLE can carry',
        );
      }
    });
  });

  group('calibration', () {
    test('a measured lap scales to the speed-1 baseline', () {
      const base = StripCalibration();
      final measured = base.calibrate(
        speed: 4,
        observed: const Duration(milliseconds: 2500),
      );

      // A 2500ms lap at speed 4 implies 10000ms at speed 1.
      expect(measured.traverseMsAtSpeed1, 10000);
      expect(measured.traverseMs(4), 2500);
    });

    test('position and dwell round-trip', () {
      const cal = StripCalibration(traverseMsAtSpeed1: 8000);
      final dwell = cal.dwellForPosition(0.35, 4);
      expect(cal.positionForDwell(dwell, 4), closeTo(0.35, 0.01));
    });

    test('positions outside the strip clamp', () {
      const cal = StripCalibration(traverseMsAtSpeed1: 8000);
      expect(cal.dwellForPosition(-1, 4), Duration.zero);
      expect(cal.dwellForPosition(5, 4), cal.dwellForPosition(1, 4));
    });

    test('a wild measurement is clamped rather than stored', () {
      const base = StripCalibration();
      final absurd = base.calibrate(
        speed: 10,
        observed: const Duration(minutes: 5),
      );
      expect(absurd.traverseMsAtSpeed1, StripCalibration.maxTraverseMs);
    });
  });

  group('calibration sweep', () {
    test('is a single sweep with no sound attached', () {
      final plan = StrikePlanner.calibrationSweep(speed: 3, length: 40);

      expect(plan.steps, hasLength(1));
      expect(plan.steps.single, isA<SweepStep>());
      expect(plan.sample, isNull);
      expect((plan.steps.single as SweepStep).effect,
          Sp621eEffects.whiteSegmentSpin);
    });
  });

  group('flicker is cheap enough to be fast', () {
    test('a flicker pulse costs a single write', () {
      final plan = planner().build(_preset(sharpness: 1.0), calibration);
      final flickers = plan.steps.whereType<FlickerStep>();

      expect(flickers, isNotEmpty);
      for (final step in flickers) {
        expect(step.writeCost, 1);
      }
    });

    test('flicker pulses sit close enough to read as one discharge', () {
      final plan = planner().build(_preset(sharpness: 1.0), calibration);

      // Find consecutive flicker pulses and check the gap between them. A
      // two-write pulse would force these to about 80ms, which is what made
      // the flicker look like a slideshow.
      var checked = 0;
      for (var i = 1; i < plan.steps.length; i++) {
        final prev = plan.steps[i - 1];
        final step = plan.steps[i];
        if (prev is! FlickerStep || step is! FlickerStep) continue;

        final gap = (step.at - prev.at).inMilliseconds;
        expect(gap, lessThanOrEqualTo(80),
            reason: 'gap between ${prev.label} and ${step.label}');
        checked++;
      }

      expect(checked, greaterThan(2), reason: 'no flicker pairs were checked');
    });

    test('the flicker burst only follows a step that set a colour', () {
      final plan = planner().build(_preset(sharpness: 1.0), calibration);

      final firstFlicker = plan.steps.indexWhere((s) => s is FlickerStep);
      expect(firstFlicker, greaterThan(0));

      // Brightness-only pulses are meaningless unless a colour is already on
      // the strip, so a flood must come first.
      final before = plan.steps.sublist(0, firstFlicker);
      expect(before.whereType<FloodStep>(), isNotEmpty);
    });

    test('a sweep that repeats its parameters is costed as one write', () {
      // The main sweep and a restrike sharing effect and speed should not be
      // charged four writes each.
      final plan = planner().build(_preset(sharpness: 1.0), calibration);
      final sweeps = plan.steps.whereType<SweepStep>().toList();

      if (sweeps.length > 1) {
        final repeats = sweeps.skip(1).where(
              (s) => s.effect == sweeps.first.effect &&
                  s.speed == sweeps.first.speed,
            );
        for (final sweep in repeats) {
          expect(sweep.writeCost, lessThan(4));
        }
      }
    });
  });

  group('bolt targeting', () {
    const bolts = [
      BoltSegment(id: 'a', name: 'Bolt A', startPixel: 10, endPixel: 50),
      BoltSegment(id: 'b', name: 'Bolt B', startPixel: 200, endPixel: 244),
    ];

    test('a targeted bolt sets the block width to the shape length', () {
      final preset = _preset().copyWith(
        placement: _preset().placement.copyWith(boltId: 'b'),
      );

      final plan = planner().build(preset, calibration, bolts: bolts);
      final sweep = plan.steps.whereType<SweepStep>().firstWhere(
            (s) => s.label.startsWith('bolt to'),
          );

      expect(sweep.length, 44, reason: 'bolt B spans 200 to 244');
    });

    test('a further bolt takes longer to reach', () {
      final near = _preset().copyWith(
        placement: _preset().placement.copyWith(boltId: 'a'),
      );
      final far = _preset().copyWith(
        placement: _preset().placement.copyWith(boltId: 'b'),
      );

      final nearPlan = planner().build(near, calibration, bolts: bolts);
      final farPlan = planner().build(far, calibration, bolts: bolts);

      expect(farPlan.mainStrokeAt, greaterThan(nearPlan.mainStrokeAt));
    });

    test('the sweep is cut at the far end of the bolt', () {
      const cal = StripCalibration(pixelCount: 288, traverseMsAtSpeed1: 10000);
      const bolt = BoltSegment(
        id: 'b',
        name: 'Bolt B',
        startPixel: 200,
        endPixel: 244,
      );

      // 244 of 288 is the moment the whole shape is lit.
      expect(bolt.positionIn(cal), closeTo(244 / 288, 0.0001));
    });

    test('a missing bolt id falls back to the raw position', () {
      final preset = _preset(position: 0.42).copyWith(
        placement: _preset(position: 0.42).placement.copyWith(boltId: 'gone'),
      );

      final resolved = planner().resolvePlacement(
        preset.placement,
        calibration,
        bolts: bolts,
      );

      expect(resolved.position, 0.42);
    });

    test('random targeting picks one of the defined bolts', () {
      final preset = _preset().copyWith(
        placement: _preset().placement.copyWith(randomBolt: true),
      );

      final widths = <int>{};
      for (var i = 0; i < 40; i++) {
        final resolved = StrikePlanner(random: Random(i)).resolvePlacement(
          preset.placement,
          calibration,
          bolts: bolts,
        );
        widths.add(resolved.width);
      }

      // Every draw must be one of the real shapes, and over 40 draws both
      // should turn up.
      expect(widths, everyElement(anyOf(40, 44)));
      expect(widths.length, 2, reason: 'random never varied');
    });

    test('bolt geometry survives a JSON round trip', () {
      const bolt = BoltSegment(
        id: 'x',
        name: 'Roof bolt',
        startPixel: 61,
        endPixel: 107,
      );
      final back = BoltSegment.fromJson(bolt.toJson());

      expect(back.id, bolt.id);
      expect(back.name, bolt.name);
      expect(back.startPixel, bolt.startPixel);
      expect(back.endPixel, bolt.endPixel);
      expect(back.length, 46);
    });

    test('defaults lay out bolts in strip order without overlapping', () {
      final defaults = BoltSegment.defaults(pixelCount: 288);
      expect(defaults, hasLength(4));

      for (var i = 1; i < defaults.length; i++) {
        expect(
          defaults[i].startPixel,
          greaterThanOrEqualTo(defaults[i - 1].endPixel),
          reason: 'bolt ${i + 1} overlaps the one before it',
        );
      }
    });
  });

  group('the planner adapts to the measured link speed', () {
    test('a slower link spreads the same strike out', () {
      final fast = StrikePlanner(random: Random(7), writeCostMs: 30)
          .build(_preset(sharpness: 1.0), calibration);
      final slow = StrikePlanner(random: Random(7), writeCostMs: 120)
          .build(_preset(sharpness: 1.0), calibration);

      expect(slow.visualDuration, greaterThan(fast.visualDuration));
    });

    test('a faster link packs flicker pulses closer together', () {
      int firstFlickerGap(StrikePlanner p) {
        final plan = p.build(_preset(sharpness: 1.0), calibration);
        for (var i = 1; i < plan.steps.length; i++) {
          if (plan.steps[i - 1] is FlickerStep &&
              plan.steps[i] is FlickerStep) {
            return (plan.steps[i].at - plan.steps[i - 1].at).inMilliseconds;
          }
        }
        return -1;
      }

      final fast = firstFlickerGap(
        StrikePlanner(random: Random(7), writeCostMs: 30),
      );
      final slow = firstFlickerGap(
        StrikePlanner(random: Random(7), writeCostMs: 120),
      );

      expect(fast, greaterThan(0));
      expect(slow, greaterThan(0));
      expect(fast, lessThan(slow));
    });

    test('placement floor widens on a slow link', () {
      final fast = StrikePlanner.minimumPlacement(
        5,
        calibration,
        writeCostMs: 30,
      );
      final slow = StrikePlanner.minimumPlacement(
        5,
        calibration,
        writeCostMs: 120,
      );

      expect(slow, greaterThan(fast));
    });
  });

  group('following a long recording', () {
    /// Six minutes of ambience with a sharp hit every two seconds, which is
    /// what a storm field recording actually looks like.
    ThunderEnvelope longAmbience() {
      final frames = <SpectralFrame>[];
      for (var i = 0; i < 18000; i++) {
        final hit = i % 100 == 0;
        frames.add(SpectralFrame(
          low: 0.4,
          mid: hit ? 0.7 : 0.05,
          high: hit ? 0.9 : 0.02,
        ));
      }
      return ThunderEnvelope(
        frames: frames,
        frameMs: 20,
        duration: const Duration(milliseconds: 18000 * 20),
      );
    }

    test('a strike does not run for the length of the file', () {
      final plan = planner().buildFromEnvelope(
        _preset(),
        calibration,
        longAmbience(),
      );

      expect(
        plan.visualDuration.inSeconds,
        lessThan(30),
        reason: 'a six-minute sample must not become a six-minute strike',
      );
    });

    test('the follow window bounds how much is used', () {
      final short = planner().buildFromEnvelope(
        _preset(),
        calibration,
        longAmbience(),
        maxFollowMs: 3000,
      );
      final long = planner().buildFromEnvelope(
        _preset(),
        calibration,
        longAmbience(),
        maxFollowMs: 9000,
      );

      expect(long.steps.length, greaterThan(short.steps.length));
    });

    test('the bolt still fires before any sound-driven flash', () {
      final plan = planner().buildFromEnvelope(
        _preset(),
        calibration,
        longAmbience(),
      );

      final firstSweep = plan.steps.indexWhere((s) => s is SweepStep);
      final firstFlicker = plan.steps.indexWhere((s) => s is FlickerStep);

      expect(firstSweep, 0);
      expect(firstFlicker, greaterThan(firstSweep));
    });

    test('an unanalysable sample still produces a valid plan', () {
      const empty = ThunderEnvelope(
        frames: [],
        frameMs: 20,
        duration: Duration.zero,
      );

      final plan =
          planner().buildFromEnvelope(_preset(), calibration, empty);

      expect(plan.steps, isNotEmpty);
      expect(plan.steps.last, isA<DarkStep>());
    });
  });

  group('auto strike', () {
    const sound = ThunderSound(
      distance: ThunderDistance.close,
      sharpness: 0.9,
      energy: 1.0,
      rumbleTailMs: 0,
      warmth: 2,
    );

    ThunderEnvelope envelopeWithHits() {
      final frames = <SpectralFrame>[];
      for (var i = 0; i < 400; i++) {
        final hit = i % 25 == 0;
        frames.add(SpectralFrame(
          low: 0.3,
          mid: hit ? 0.7 : 0.04,
          high: hit ? 0.9 : 0.02,
        ));
      }
      return ThunderEnvelope(
        frames: frames,
        frameMs: 20,
        duration: const Duration(milliseconds: 8000),
      );
    }

    test('lights a segment inside the requested LED range', () {
      for (var seed = 0; seed < 25; seed++) {
        final plan = StrikePlanner(random: Random(seed)).buildAutoStrike(
          sound,
          calibration,
          envelopeWithHits(),
        );

        final sweep = plan.steps.whereType<SweepStep>().first;
        expect(sweep.length, inInclusiveRange(30, 50));
      }
    });

    test('picks a different stretch each time', () {
      final positions = <String>{};
      for (var seed = 0; seed < 20; seed++) {
        final plan = StrikePlanner(random: Random(seed)).buildAutoStrike(
          sound,
          calibration,
          envelopeWithHits(),
        );
        positions.add(plan.presetName);
      }

      expect(positions.length, greaterThan(5),
          reason: 'placement and width should vary between strikes');
    });

    test('holds the segment still rather than letting it sail away', () {
      final plan = StrikePlanner(random: Random(3)).buildAutoStrike(
        sound,
        calibration,
        envelopeWithHits(),
      );

      final sweeps = plan.steps.whereType<SweepStep>().toList();
      expect(sweeps.length, greaterThanOrEqualTo(2));

      // The second sweep drops the speed and changes nothing else, so it costs
      // a single write.
      final hold = sweeps[1];
      expect(hold.speed, lessThan(sweeps[0].speed));
      expect(hold.length, sweeps[0].length);
      expect(hold.writeCost, 1);
    });

    test('the bolt lights alone before any whole-strip wash', () {
      final plan = StrikePlanner(random: Random(5)).buildAutoStrike(
        sound,
        calibration,
        envelopeWithHits(),
      );

      final firstFlood = plan.steps.indexWhere((s) => s is FloodStep);
      expect(firstFlood, greaterThan(0));

      // The wash is the sky lighting up after the bolt, so the segment must
      // have struck and blinked before the whole strip comes on.
      expect(
        plan.steps[firstFlood].at,
        greaterThan(plan.mainStrokeAt),
        reason: 'the whole strip must not light before the bolt does',
      );
    });

    test('the wash carries the strike colour, which the bolt cannot', () {
      final plan = StrikePlanner(random: Random(5)).buildAutoStrike(
        sound,
        calibration,
        envelopeWithHits(),
      );

      final wash = plan.steps.whereType<FloodStep>().first;
      final (r, g, b) = sound.strikeColor;

      expect([wash.r, wash.g, wash.b], [r, g, b]);
      expect(wash.b, greaterThan(wash.r),
          reason: 'a close strike lights the sky blue-white');
    });

    test('the wash can be turned off', () {
      final plan = StrikePlanner(random: Random(5)).buildAutoStrike(
        sound,
        calibration,
        envelopeWithHits(),
        skyWash: false,
      );

      expect(plan.steps.whereType<FloodStep>(), isEmpty);
    });

    test('a flash is over quickly, like a real one', () {
      for (var seed = 0; seed < 15; seed++) {
        final plan = StrikePlanner(random: Random(seed)).buildAutoStrike(
          sound,
          calibration,
          envelopeWithHits(),
        );

        final flash = plan.visualDuration - plan.mainStrokeAt;
        expect(flash.inMilliseconds, lessThan(1600));
      }
    });

    test('strokes decay rather than switching on and off', () {
      final plan = StrikePlanner(random: Random(11)).buildAutoStrike(
        sound,
        calibration,
        null,
      );

      final levels = plan.steps
          .whereType<FlickerStep>()
          .map((s) => s.brightness)
          .toList();

      // A decaying tail means at least one run of three successively dimmer
      // levels, which a square blink never produces.
      var sawDecay = false;
      for (var i = 2; i < levels.length; i++) {
        if (levels[i - 2] > levels[i - 1] && levels[i - 1] > levels[i]) {
          sawDecay = true;
          break;
        }
      }

      expect(sawDecay, isTrue, reason: 'levels were $levels');
    });

    test('the blink pattern comes from the recording', () {
      final withSound = StrikePlanner(random: Random(9)).buildAutoStrike(
        sound,
        calibration,
        envelopeWithHits(),
      );
      final without = StrikePlanner(random: Random(9)).buildAutoStrike(
        sound,
        calibration,
        null,
      );

      expect(withSound.steps.whereType<FlickerStep>(), isNotEmpty);
      expect(
        withSound.steps.length,
        isNot(without.steps.length),
        reason: 'an analysed recording should not blink like the fallback',
      );
    });

    test('the segment travels unlit, so nothing lights in series', () {
      for (var seed = 0; seed < 15; seed++) {
        final plan = StrikePlanner(random: Random(seed)).buildAutoStrike(
          sound,
          calibration,
          envelopeWithHits(),
        );

        // Every sweep is the block moving into place, and none of them may be
        // visible: a lit moving block is exactly the chase this avoids.
        for (final sweep in plan.steps.whereType<SweepStep>()) {
          expect(sweep.brightness, 0, reason: sweep.label);
        }
      }
    });

    test('the whole segment appears in one write', () {
      final plan = StrikePlanner(random: Random(2)).buildAutoStrike(
        sound,
        calibration,
        envelopeWithHits(),
      );

      final firstLit = plan.steps.firstWhere(
        (s) => s is FlickerStep && s.brightness > 8,
      );

      expect(firstLit.writeCost, 1);
      expect(firstLit.at, plan.mainStrokeAt,
          reason: 'the strike is the moment the segment lights');
    });

    test('the blink is brief, so the held segment cannot drift far', () {
      for (var seed = 0; seed < 15; seed++) {
        final plan = StrikePlanner(random: Random(seed)).buildAutoStrike(
          sound,
          calibration,
          envelopeWithHits(),
        );

        final blink = plan.visualDuration - plan.mainStrokeAt;
        expect(
          blink.inMilliseconds,
          lessThan(2500),
          reason: 'a long blink lets the segment wander off its LEDs',
        );
      }
    });

    test('the blink goes dark between hits rather than fading', () {
      final plan = StrikePlanner(random: Random(4)).buildAutoStrike(
        sound,
        calibration,
        envelopeWithHits(),
      );

      final levels = plan.steps
          .whereType<FlickerStep>()
          .map((s) => s.brightness)
          .toList();

      expect(levels.any((l) => l <= 8), isTrue,
          reason: 'there must be dark gaps for it to read as blinking');
      expect(levels.any((l) => l > 128), isTrue);
    });

    test('still produces a strike with no analysis available', () {
      final plan = StrikePlanner(random: Random(9)).buildAutoStrike(
        sound,
        calibration,
        null,
      );

      expect(plan.steps.whereType<FlickerStep>(), isNotEmpty);
      expect(plan.steps.last, isA<DarkStep>());
    });

    test('always ends dark so the strip returns to the glow', () {
      for (var seed = 0; seed < 15; seed++) {
        final plan = StrikePlanner(random: Random(seed)).buildAutoStrike(
          sound,
          calibration,
          envelopeWithHits(),
        );
        expect(plan.steps.last, isA<DarkStep>());
      }
    });

    test('placement stays clear of the unreachable near end', () {
      final floor = StrikePlanner.minimumPlacement(7, calibration);

      for (var seed = 0; seed < 20; seed++) {
        final plan = StrikePlanner(random: Random(seed)).buildAutoStrike(
          sound,
          calibration,
          envelopeWithHits(),
        );

        final percent = int.parse(
          RegExp(r'at (\d+)%').firstMatch(plan.presetName)!.group(1)!,
        );
        expect(percent / 100, greaterThanOrEqualTo(floor - 0.01));
      }
    });
  });
}
