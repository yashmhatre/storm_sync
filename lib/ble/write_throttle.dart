import 'dart:async';

import 'package:clock/clock.dart';

/// Rate-limits outbound commands, independently per bucket.
///
/// A slider fires `onChanged` dozens of times a second; a BLE connection
/// interval is typically 15-50 ms and a flooded link stops being responsive
/// long before the queue drains. This class keeps at most one command per
/// [interval] per bucket, dropping the intermediate values -- they are stale
/// the moment the next one arrives.
///
/// The contract that makes dropping safe is [submit] with `isFinal: true`,
/// which always sends. Wire it to `onChangeEnd` and the value the user
/// actually settled on is guaranteed to reach the device, even if it lands
/// inside a throttle window that would otherwise have swallowed it.
///
/// Uses `package:clock` rather than [DateTime.now] so tests can drive it with
/// `fakeAsync` instead of real sleeps.
class WriteThrottle {
  WriteThrottle({required this.interval, required this.onSend});

  /// Minimum gap between two sends in the same bucket. 100 ms is the ten
  /// writes per second the firmware link is comfortable with.
  final Duration interval;

  /// Where a command goes once the throttle decides to release it.
  final void Function(String command) onSend;

  final Map<String, Timer> _timers = {};
  final Map<String, String> _pending = {};
  final Map<String, DateTime> _lastSent = {};

  /// Number of buckets holding a value that has not been sent yet.
  int get pendingCount => _pending.length;

  /// Offers [command] for [bucket].
  ///
  /// Buckets are usually a parameter key, so dragging brightness never
  /// starves a colour change happening at the same time.
  void submit(String bucket, String command, {required bool isFinal}) {
    _timers.remove(bucket)?.cancel();

    if (isFinal) {
      _pending.remove(bucket);
      _lastSent[bucket] = clock.now();
      onSend(command);
      return;
    }

    final now = clock.now();
    final last = _lastSent[bucket];
    final elapsed = last == null ? interval : now.difference(last);

    if (elapsed >= interval) {
      _pending.remove(bucket);
      _lastSent[bucket] = now;
      onSend(command);
      return;
    }

    // Inside the window. Hold the newest value and release it when the window
    // closes; anything submitted before then is overwritten and never sent.
    _pending[bucket] = command;
    _timers[bucket] = Timer(interval - elapsed, () {
      _timers.remove(bucket);
      final queued = _pending.remove(bucket);
      if (queued == null) return;
      _lastSent[bucket] = clock.now();
      onSend(queued);
    });
  }

  /// Drops everything queued and forgets the rate-limit history.
  ///
  /// Called on disconnect: a value queued against the old link is not worth
  /// delivering to a new one.
  void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _pending.clear();
    _lastSent.clear();
  }
}
