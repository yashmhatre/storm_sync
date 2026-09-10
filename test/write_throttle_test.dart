import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storm_sync/ble/write_throttle.dart';

void main() {
  group('WriteThrottle', () {
    const interval = Duration(milliseconds: 100);

    /// Simulates a slider drag: [count] updates spread over [over].
    List<String> drag({
      required int count,
      required Duration over,
      required bool sendFinal,
    }) {
      final sent = <String>[];
      fakeAsync((async) {
        final throttle = WriteThrottle(
          interval: interval,
          onSend: sent.add,
        );
        final step = Duration(microseconds: over.inMicroseconds ~/ count);
        for (var i = 1; i <= count; i++) {
          throttle.submit('bri', 'SET bri $i', isFinal: false);
          async.elapse(step);
        }
        if (sendFinal) {
          throttle.submit('bri', 'SET bri $count', isFinal: true);
        }
        // Let any trailing timer fire.
        async.elapse(interval * 2);
      });
      return sent;
    }

    test('caps a one-second drag at ten writes', () {
      // 60 onChanged callbacks in one second, as a real drag produces.
      final sent = drag(
        count: 60,
        over: const Duration(seconds: 1),
        sendFinal: false,
      );

      // Ten windows in a second, plus at most one trailing release.
      expect(sent.length, lessThanOrEqualTo(11));
      expect(sent.length, greaterThan(5), reason: 'should not stall entirely');
    });

    test('sends the first value immediately', () {
      final sent = <String>[];
      fakeAsync((async) {
        WriteThrottle(interval: interval, onSend: sent.add)
            .submit('bri', 'SET bri 10', isFinal: false);
        expect(sent, ['SET bri 10']);
        async.elapse(interval * 2);
      });
    });

    test('always delivers the final value, even inside the window', () {
      final sent = <String>[];
      fakeAsync((async) {
        final throttle = WriteThrottle(interval: interval, onSend: sent.add);
        throttle.submit('bri', 'SET bri 1', isFinal: false);
        async.elapse(const Duration(milliseconds: 5));
        // Well inside the 100 ms window, so this would normally be deferred.
        throttle.submit('bri', 'SET bri 200', isFinal: true);
        expect(sent.last, 'SET bri 200');
        async.elapse(interval * 2);
      });

      // And it is not sent twice by a trailing timer.
      expect(sent.where((c) => c == 'SET bri 200'), hasLength(1));
    });

    test('the last value of a drag always arrives', () {
      final sent = drag(
        count: 60,
        over: const Duration(seconds: 1),
        sendFinal: true,
      );
      expect(sent.last, 'SET bri 60');
    });

    test('drops intermediate values rather than queueing them', () {
      final sent = <String>[];
      fakeAsync((async) {
        final throttle = WriteThrottle(interval: interval, onSend: sent.add);
        throttle.submit('bri', 'SET bri 1', isFinal: false); // sent now
        for (var i = 2; i <= 20; i++) {
          throttle.submit('bri', 'SET bri $i', isFinal: false);
          async.elapse(const Duration(milliseconds: 1));
        }
        async.elapse(interval * 2);
      });

      // One immediate plus one trailing release carrying the newest value.
      expect(sent, ['SET bri 1', 'SET bri 20']);
    });

    test('throttles each bucket independently', () {
      final sent = <String>[];
      fakeAsync((async) {
        final throttle = WriteThrottle(interval: interval, onSend: sent.add);
        throttle.submit('bri', 'SET bri 1', isFinal: false);
        throttle.submit('drift', 'SET drift 4', isFinal: false);
        throttle.submit('COLOR', 'COLOR 255 0 0', isFinal: false);
        async.elapse(interval * 2);
      });

      // A busy brightness drag must not starve the other two.
      expect(sent, ['SET bri 1', 'SET drift 4', 'COLOR 255 0 0']);
    });

    test('cancelAll drops queued values', () {
      final sent = <String>[];
      fakeAsync((async) {
        final throttle = WriteThrottle(interval: interval, onSend: sent.add);
        throttle.submit('bri', 'SET bri 1', isFinal: false);
        throttle.submit('bri', 'SET bri 2', isFinal: false);
        expect(throttle.pendingCount, 1);

        throttle.cancelAll();
        async.elapse(interval * 2);
      });

      expect(sent, ['SET bri 1']);
    });
  });
}
