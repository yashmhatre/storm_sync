import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storm_sync/audio/sound_pack.dart';
import 'package:storm_sync/audio/thunder_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SoundPack model', () {
    test('defaultPack correctly maps to bundled assets', () {
      final pack = SoundPack.defaultPack;
      expect(pack.isBuiltIn, isTrue);

      expect(pack.isAssetFor(ThunderDistance.close), isTrue);
      expect(pack.isAssetFor(ThunderDistance.mid), isTrue);
      expect(pack.isAssetFor(ThunderDistance.far), isTrue);

      expect(pack.audioPathFor(ThunderDistance.close), ThunderDistance.close.asset);
      expect(pack.audioPathFor(ThunderDistance.mid), ThunderDistance.mid.asset);
      expect(pack.audioPathFor(ThunderDistance.far), ThunderDistance.far.asset);
    });

    test('custom sound pack distinguishes custom paths from bundled assets', () {
      const custom = SoundPack(
        id: 'alpine_pack',
        name: 'Alpine Pack',
        description: 'Recorded in mountains',
        closeAudioPath: '/data/user/0/app/close.wav',
        midAudioPath: null, // Should fall back to bundled asset
        farAudioPath: '/data/user/0/app/far.mp3',
        isBuiltIn: false,
      );

      expect(custom.isAssetFor(ThunderDistance.close), isFalse);
      expect(custom.audioPathFor(ThunderDistance.close), '/data/user/0/app/close.wav');

      expect(custom.isAssetFor(ThunderDistance.mid), isTrue);
      expect(custom.audioPathFor(ThunderDistance.mid), ThunderDistance.mid.asset);

      expect(custom.isAssetFor(ThunderDistance.far), isFalse);
      expect(custom.audioPathFor(ThunderDistance.far), '/data/user/0/app/far.mp3');

      // Serialization roundtrip
      final json = custom.toJson();
      final restored = SoundPack.fromJson(json);
      expect(restored.id, custom.id);
      expect(restored.name, custom.name);
      expect(restored.closeAudioPath, custom.closeAudioPath);
      expect(restored.midAudioPath, isNull);
    });
  });

  group('SoundPackManager', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initializes with default pack when empty', () async {
      final manager = await SoundPackManager.load();
      expect(manager.packs.length, 1);
      expect(manager.activePack.id, SoundPack.defaultPack.id);
      expect(manager.activePack.name, SoundPack.defaultPack.name);
    });

    test('creates and persists custom sound pack', () async {
      final manager = await SoundPackManager.load();
      final created = await manager.createPack(
        name: 'Thunder HD',
        description: 'High fidelity audio',
        closePath: '/path/to/close.mp3',
        midPath: '/path/to/mid.mp3',
      );

      expect(manager.packs.length, 2);
      expect(manager.activePackId, created.id);
      expect(manager.activePack.name, 'Thunder HD');

      // Check persistence across new manager instance
      final reloaded = await SoundPackManager.load();
      expect(reloaded.packs.length, 2);
      expect(reloaded.activePackId, created.id);
      expect(reloaded.activePack.closeAudioPath, '/path/to/close.mp3');
    });

    test('deletes custom pack and falls back to default', () async {
      final manager = await SoundPackManager.load();
      final created = await manager.createPack(
        name: 'Ephemeral Pack',
        description: 'To be removed',
      );

      expect(manager.packs.length, 2);
      expect(manager.activePackId, created.id);

      await manager.deletePack(created.id);
      expect(manager.packs.length, 1);
      expect(manager.activePackId, SoundPack.defaultPack.id);

      // Attempting to delete default pack is a safe no-op
      await manager.deletePack(SoundPack.defaultPack.id);
      expect(manager.packs.length, 1);
    });
  });
}

