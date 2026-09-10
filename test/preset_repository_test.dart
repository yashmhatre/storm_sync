import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storm_sync/ble/storm_service.dart';
import 'package:storm_sync/model/app_settings.dart';
import 'package:storm_sync/model/preset.dart';
import 'package:storm_sync/model/preset_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Preset model', () {
    test('serializes and deserializes cleanly', () {
      const preset = Preset(
        id: 'test_id',
        name: 'Midnight Rumble',
        description: 'Test description',
        parameters: {'bri': 180, 'storm_min': 1000},
        boltColor: RgbColor(255, 200, 150),
        cloudTint: RgbColor(30, 40, 90),
        speakerLatencyMs: 250,
        isBuiltIn: false,
      );

      final json = preset.toJson();
      final revived = Preset.fromJson(json);

      expect(revived.id, preset.id);
      expect(revived.name, preset.name);
      expect(revived.description, preset.description);
      expect(revived.parameters, preset.parameters);
      expect(revived.boltColor, preset.boltColor);
      expect(revived.cloudTint, preset.cloudTint);
      expect(revived.speakerLatencyMs, 250);
      expect(revived.isBuiltIn, false);
    });

    test('built-in presets provide required factory configurations', () {
      expect(Preset.builtInPresets.length, greaterThanOrEqualTo(4));
      final ids = Preset.builtInPresets.map((p) => p.id).toSet();
      expect(ids.contains('default_storm'), isTrue);
      expect(ids.contains('summer_heat'), isTrue);
      expect(ids.contains('violent_gale'), isTrue);
      expect(ids.contains('alien_aurora'), isTrue);

      for (final preset in Preset.builtInPresets) {
        expect(preset.isBuiltIn, isTrue);
        expect(preset.parameters.containsKey('bri'), isTrue);
        expect(preset.parameters.containsKey('storm_min'), isTrue);
      }
    });
  });

  group('PresetRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('loads factory presets when no custom presets are saved', () async {
      final repo = await PresetRepository.load();
      expect(repo.presets.length, equals(Preset.builtInPresets.length));
      expect(repo.activePreset, isNull);
    });

    test('saves and persists a new custom preset', () async {
      final repo = await PresetRepository.load();
      final storm = StormService();
      storm.setParameter('bri', 215, finalValue: true);
      storm.setColor(180, 220, 255, finalValue: true);
      storm.setTint(15, 25, 75, finalValue: true);

      final settings = await AppSettings.load();
      settings.speakerLatencyMs = 280;

      final saved = await repo.saveCurrentState(
        name: 'My Custom Storm',
        description: 'Tuned for living room',
        stormService: storm,
        appSettings: settings,
      );

      expect(repo.presets.length, equals(Preset.builtInPresets.length + 1));
      expect(repo.activePresetId, equals(saved.id));
      expect(repo.activePreset?.name, equals('My Custom Storm'));
      expect(repo.activePreset?.boltColor.r, equals(180));
      expect(repo.activePreset?.speakerLatencyMs, equals(280));

      // Check persistence across new repository instance
      final reloadedRepo = await PresetRepository.load();
      expect(reloadedRepo.presets.length, equals(Preset.builtInPresets.length + 1));
      expect(reloadedRepo.activePresetId, equals(saved.id));
      expect(reloadedRepo.activePreset?.name, equals('My Custom Storm'));
    });

    test('applies preset to StormService and AppSettings', () async {
      final repo = await PresetRepository.load();
      final storm = StormService();
      final settings = await AppSettings.load();

      final target = Preset.builtInPresets.firstWhere((p) => p.id == 'summer_heat');
      await repo.applyPreset(target, storm, settings);

      expect(repo.activePresetId, equals('summer_heat'));
      expect(storm.parameters['bri'], equals(160));
      expect(storm.boltColor, equals([255, 225, 170]));
      expect(storm.tintColor, equals([120, 60, 20]));
    });

    test('deletes custom preset without deleting built-in presets', () async {
      final repo = await PresetRepository.load();
      final storm = StormService();
      final settings = await AppSettings.load();

      final custom = await repo.saveCurrentState(
        name: 'Temporary Preset',
        description: 'To be deleted',
        stormService: storm,
        appSettings: settings,
      );

      expect(repo.presets.any((p) => p.id == custom.id), isTrue);

      await repo.deletePreset(custom.id);
      expect(repo.presets.any((p) => p.id == custom.id), isFalse);

      // Attempting to delete a built-in preset is a no-op
      await repo.deletePreset('default_storm');
      expect(repo.presets.any((p) => p.id == 'default_storm'), isTrue);
    });
  });
}

