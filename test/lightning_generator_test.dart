import 'package:flutter_test/flutter_test.dart';
import 'package:storm_sync/lightning/lightning_engine.dart';

void main() {
  group('LightningGenerator Tests', () {
    test('same seed gives same strike', () {
      final genA = LightningGenerator(seed: 42);
      final genB = LightningGenerator(seed: 42);

      final strikeA = genA.generate(LightningProfile.normal);
      final strikeB = genB.generate(LightningProfile.normal);

      expect(strikeA.pulses.length, equals(strikeB.pulses.length));
      expect(strikeA.thunderDelay, equals(strikeB.thunderDelay));
      
      for (int i = 0; i < strikeA.pulses.length; i++) {
        expect(strikeA.pulses[i].type, equals(strikeB.pulses[i].type));
        expect(strikeA.pulses[i].duration, equals(strikeB.pulses[i].duration));
        expect(strikeA.pulses[i].intensity, equals(strikeB.pulses[i].intensity));
      }
    });

    test('durations are never below configured BLE minimum (except 0 length pulses which are impossible)', () {
      final gen = LightningGenerator(seed: 123);
      final strike = gen.generate(LightningProfile.normal);

      for (final pulse in strike.pulses) {
        expect(pulse.duration.inMilliseconds, greaterThanOrEqualTo(22)); // the lowest in presets
      }
    });

    test('brightness remains 0-255 and RGB remains 0-255', () {
      final gen = LightningGenerator(seed: 999);
      final strike = gen.generate(LightningProfile.violent); // violent has 1.0 intensity

      for (final pulse in strike.pulses) {
        expect(pulse.intensity, greaterThanOrEqualTo(0.0));
        expect(pulse.intensity, lessThanOrEqualTo(1.0));
        
        expect(pulse.red, greaterThanOrEqualTo(0));
        expect(pulse.red, lessThanOrEqualTo(255));
        expect(pulse.green, greaterThanOrEqualTo(0));
        expect(pulse.green, lessThanOrEqualTo(255));
        expect(pulse.blue, greaterThanOrEqualTo(0));
        expect(pulse.blue, lessThanOrEqualTo(255));
      }
    });
    
    test('normal profile includes valid main stroke', () {
      final gen = LightningGenerator();
      final strike = gen.generate(LightningProfile.normal);
      
      final mainStrokes = strike.pulses.where((p) => p.type == LightningPulseType.mainStroke).toList();
      expect(mainStrokes.length, equals(1));
      expect(mainStrokes.first.intensity, greaterThanOrEqualTo(0.92));
    });
  });
}
