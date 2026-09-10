import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storm_sync/audio/sequence_engine.dart';
import 'package:storm_sync/audio/thunder_player.dart';
import 'package:storm_sync/ble/storm_service.dart';
import 'package:storm_sync/model/app_settings.dart';
import 'package:storm_sync/model/storm_sequence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SequenceEngine', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('executes steps in sequence matching delays and finishes completed', () {
      fakeAsync((async) {
        final engine = SequenceEngine();
        final storm = StormService();
        final thunder = ThunderPlayer();
        late final AppSettings settings;

        async.run((_) async {
          settings = await AppSettings.load();
        });
        async.flushMicrotasks();

        const sequence = StormSequence(
          id: 'test_seq',
          name: 'Test Sequence',
          description: 'Testing step execution',
          steps: [
            SequenceStep(
              delayBeforeMs: 500,
              command: 'SHEET',
              distance: ThunderDistance.far,
            ),
            SequenceStep(
              delayBeforeMs: 1000,
              command: 'STRIKE 200',
              distance: ThunderDistance.close,
            ),
          ],
        );

        engine.start(
          sequence: sequence,
          stormService: storm,
          thunderPlayer: thunder,
          appSettings: settings,
        );

        expect(engine.isRunning, isTrue);

        // Advance 500ms: step 0 executes
        async.elapse(const Duration(milliseconds: 500));
        expect(engine.currentStepIndex, 0);
        expect(engine.isRunning, isTrue);

        // Advance 1000ms: step 1 executes and finishes
        async.elapse(const Duration(milliseconds: 1000));
        expect(engine.currentStepIndex, 1);
        expect(engine.status, SequenceStatus.completed);
        expect(engine.progress, 1.0);
        expect(engine.isRunning, isFalse);
      });
    });

    test('stopping sequence aborts pending steps immediately', () {
      fakeAsync((async) {
        final engine = SequenceEngine();
        final storm = StormService();
        final thunder = ThunderPlayer();
        late final AppSettings settings;

        async.run((_) async {
          settings = await AppSettings.load();
        });
        async.flushMicrotasks();

        const sequence = StormSequence(
          id: 'abort_seq',
          name: 'Abort Sequence',
          description: 'Testing abort',
          steps: [
            SequenceStep(delayBeforeMs: 200, command: 'SHEET'),
            SequenceStep(delayBeforeMs: 5000, command: 'STRIKE 255'),
          ],
        );

        engine.start(
          sequence: sequence,
          stormService: storm,
          thunderPlayer: thunder,
          appSettings: settings,
        );

        async.elapse(const Duration(milliseconds: 200));
        expect(engine.currentStepIndex, 0);

        engine.stop();
        expect(engine.isRunning, isFalse);
        expect(engine.status, SequenceStatus.idle);
        expect(engine.currentStepIndex, -1);

        // Advance past step 1's time: should NOT fire
        async.elapse(const Duration(milliseconds: 6000));
        expect(engine.isRunning, isFalse);
      });
    });

    test('looping sequence re-executes from first step', () {
      fakeAsync((async) {
        final engine = SequenceEngine();
        final storm = StormService();
        final thunder = ThunderPlayer();
        late final AppSettings settings;

        async.run((_) async {
          settings = await AppSettings.load();
        });
        async.flushMicrotasks();

        const sequence = StormSequence(
          id: 'loop_seq',
          name: 'Loop Sequence',
          description: 'Testing loop',
          isLooping: true,
          steps: [
            SequenceStep(delayBeforeMs: 300, command: 'SHEET'),
            SequenceStep(delayBeforeMs: 300, command: 'STRIKE 100'),
          ],
        );

        engine.start(
          sequence: sequence,
          stormService: storm,
          thunderPlayer: thunder,
          appSettings: settings,
        );

        // Step 0 fires
        async.elapse(const Duration(milliseconds: 300));
        expect(engine.currentStepIndex, 0);
        expect(engine.iteration, 1);

        // Step 1 fires
        async.elapse(const Duration(milliseconds: 300));
        expect(engine.currentStepIndex, 1);

        // Loops into second iteration (Step 0)
        async.elapse(const Duration(milliseconds: 300));
        expect(engine.iteration, 2);
        expect(engine.currentStepIndex, 0);

        engine.stop();
        expect(engine.isRunning, isFalse);
      });
    });
  });
}

