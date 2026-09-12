import 'dart:async';
import 'package:flutter/foundation.dart';
import 'lightning_models.dart';

typedef WriteColorCallback = Future<void> Function(int r, int g, int b);
typedef PlayAudioCallback = void Function(Duration delayMs);

class LightningScheduler {
  final WriteColorCallback writeColor;
  final PlayAudioCallback playThunder;
  
  // Absolute minimum BLE interval to prevent packet dropping
  static const int minimumBlePulseIntervalMs = 25;

  bool _isCancelled = false;

  LightningScheduler({
    required this.writeColor,
    required this.playThunder,
  });

  void cancel() {
    _isCancelled = true;
  }

  Future<void> execute(LightningSequence sequence) async {
    _isCancelled = false;

    // Trigger audio async
    playThunder(sequence.thunderDelay);

    final clock = Stopwatch()..start();
    
    int lastR = -1;
    int lastG = -1;
    int lastB = -1;

    Duration targetTime = Duration.zero;

    for (int i = 0; i < sequence.pulses.length; i++) {
      if (_isCancelled) break;

      final pulse = sequence.pulses[i];
      
      // Ensure the pulse is at least the minimum BLE safe interval
      final safeDuration = pulse.duration.inMilliseconds < minimumBlePulseIntervalMs 
          ? const Duration(milliseconds: minimumBlePulseIntervalMs)
          : pulse.duration;

      // Debug logging
      if (kDebugMode) {
        print('LIGHTNING ${pulse.type.name} int=${(pulse.intensity*100).round()}% dur=${safeDuration.inMilliseconds}ms at ${targetTime.inMilliseconds}ms');
      }

      // Wait until it's time for this pulse to fire
      final wait = targetTime - clock.elapsed;
      if (wait > Duration.zero) {
        await Future.delayed(wait);
      }
      
      if (_isCancelled) break;

      // Only send BLE command if color has actually changed
      if (pulse.red != lastR || pulse.green != lastG || pulse.blue != lastB) {
        await writeColor(pulse.red, pulse.green, pulse.blue);
        lastR = pulse.red;
        lastG = pulse.green;
        lastB = pulse.blue;
      }

      // Advance target timeline
      targetTime += safeDuration;
    }
    
    // Final wait to ensure the last pulse finishes its duration before we yield control
    final wait = targetTime - clock.elapsed;
    if (wait > Duration.zero && !_isCancelled) {
      await Future.delayed(wait);
    }

    clock.stop();
  }
}
