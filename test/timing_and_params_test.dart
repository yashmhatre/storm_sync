import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storm_sync/audio/thunder_player.dart';
import 'package:storm_sync/model/app_settings.dart';
import 'package:storm_sync/model/params.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('audio delay', () {
    Future<AppSettings> settingsWith(int latencyMs) async {
      SharedPreferences.setMockInitialValues({
        'speaker_latency_ms': latencyMs,
      });
      return AppSettings.load();
    }

    test('subtracts speaker latency from the distance delay', () async {
      final settings = await settingsWith(200);

      expect(
        settings.audioDelayFor(ThunderDistance.close.distanceDelayMs),
        const Duration(milliseconds: 50), // 250 - 200
      );
      expect(
        settings.audioDelayFor(ThunderDistance.mid.distanceDelayMs),
        const Duration(milliseconds: 1200), // 1400 - 200
      );
      expect(
        settings.audioDelayFor(ThunderDistance.far.distanceDelayMs),
        const Duration(milliseconds: 4000), // 4200 - 200
      );
    });

    test('clamps at zero when the speaker lags more than the distance',
        () async {
      final settings = await settingsWith(600);
      // 250 - 600 would be negative; the best we can do is play immediately.
      expect(
        settings.audioDelayFor(ThunderDistance.close.distanceDelayMs),
        Duration.zero,
      );
    });

    test('defaults to 200 ms and persists a change', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      expect(settings.speakerLatencyMs, AppSettings.defaultSpeakerLatencyMs);

      settings.speakerLatencyMs = 340;
      // The setter writes through; a fresh load sees it.
      final reloaded = await AppSettings.load();
      expect(reloaded.speakerLatencyMs, 340);
    });

    test('latency is clamped to the slider range', () async {
      final settings = await settingsWith(200);
      settings.speakerLatencyMs = 9999;
      expect(settings.speakerLatencyMs, AppSettings.maxSpeakerLatencyMs);
      settings.speakerLatencyMs = -50;
      expect(settings.speakerLatencyMs, AppSettings.minSpeakerLatencyMs);
    });
  });

  group('distance delays match the brief', () {
    test('close 250, mid 1400, far 4200', () {
      expect(ThunderDistance.close.distanceDelayMs, 250);
      expect(ThunderDistance.mid.distanceDelayMs, 1400);
      expect(ThunderDistance.far.distanceDelayMs, 4200);
    });
  });

  group('ParamSpec', () {
    test('covers every documented key exactly once', () {
      const expected = {
        'bri', 'glow_floor', 'glow_range', 'drift', 'noise_scale',
        'fork_max', 'stroke_max', 'fade_close', 'fade_far', 'sheet_ratio',
        'rumble_rate', 'storm_min', 'storm_max',
      };
      expect(kParamsByKey.keys.toSet(), expected);
      expect(kAllParams, hasLength(expected.length));
    });

    test('ranges match the firmware clamps', () {
      void check(String key, int min, int max) {
        final spec = kParamsByKey[key]!;
        expect(spec.min, min, reason: '$key min');
        expect(spec.max, max, reason: '$key max');
      }

      check('bri', 0, 255);
      check('glow_floor', 0, 80);
      check('glow_range', 0, 80);
      check('drift', 1, 8);
      check('noise_scale', 1, 40);
      check('fork_max', 0, 3);
      check('stroke_max', 1, 8);
      check('fade_close', 180, 250);
      check('fade_far', 180, 250);
      check('sheet_ratio', 0, 255);
      check('rumble_rate', 1, 20);
      check('storm_min', 500, 10000);
      check('storm_max', 2000, 30000);
    });

    test('clamps out-of-range values', () {
      final drift = kParamsByKey['drift']!;
      expect(drift.clampValue(0), 1);
      expect(drift.clampValue(99), 8);
      expect(drift.clampValue(4), 4);
    });

    test('snaps to the step and never leaves the range', () {
      final stormMin = kParamsByKey['storm_min']!;
      expect(stormMin.step, 100);
      expect(stormMin.snap(1234), 1200);
      expect(stormMin.snap(1250), 1300);
      // The top of the range is reachable and nothing overshoots it.
      expect(stormMin.snap(10000), 10000);
      expect(stormMin.snap(99999), 10000);
      expect(stormMin.snap(-1), 500);
    });

    test('every spec offers at least one division', () {
      for (final spec in kAllParams) {
        expect(spec.divisions, greaterThan(0), reason: spec.key);
      }
    });
  });
}
