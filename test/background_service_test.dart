import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storm_sync/audio/thunder_player.dart';
import 'package:storm_sync/ble/background_service.dart';
import 'package:storm_sync/ble/storm_service.dart';
import 'package:storm_sync/model/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationAction', () {
    test('resolves from valid action IDs', () {
      expect(
        NotificationAction.fromId('action_strike_near'),
        NotificationAction.strikeNear,
      );
      expect(
        NotificationAction.fromId('action_sheet'),
        NotificationAction.sheet,
      );
      expect(
        NotificationAction.fromId('action_glow'),
        NotificationAction.glow,
      );
      expect(
        NotificationAction.fromId('action_off'),
        NotificationAction.off,
      );
    });

    test('returns null for unknown action IDs', () {
      expect(NotificationAction.fromId(null), isNull);
      expect(NotificationAction.fromId('unknown_action'), isNull);
    });
  });

  group('BackgroundRemoteService action dispatch', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('dispatches strikeNear command to StormService and ThunderPlayer', () async {
      final bg = BackgroundRemoteService();
      final storm = StormService();
      final thunder = ThunderPlayer();
      final settings = await AppSettings.load();

      bg.dispatchAction(
        action: NotificationAction.strikeNear,
        stormService: storm,
        thunderPlayer: thunder,
        appSettings: settings,
      );
      await Future<void>.delayed(Duration.zero);

      expect(storm.log.isNotEmpty, isTrue);
      expect(storm.log.any((l) => l.text.contains('STRIKE 230')), isTrue);
    });

    test('dispatches sheet command to StormService', () async {
      final bg = BackgroundRemoteService();
      final storm = StormService();
      final thunder = ThunderPlayer();
      final settings = await AppSettings.load();

      bg.dispatchAction(
        action: NotificationAction.sheet,
        stormService: storm,
        thunderPlayer: thunder,
        appSettings: settings,
      );
      await Future<void>.delayed(Duration.zero);

      expect(storm.log.any((l) => l.text.contains('SHEET')), isTrue);
    });

    test('dispatches glow and off modes to StormService', () async {
      final bg = BackgroundRemoteService();
      final storm = StormService();
      final thunder = ThunderPlayer();
      final settings = await AppSettings.load();

      bg.dispatchAction(
        action: NotificationAction.glow,
        stormService: storm,
        thunderPlayer: thunder,
        appSettings: settings,
      );
      expect(storm.mode, equals('GLOW'));

      bg.dispatchAction(
        action: NotificationAction.off,
        stormService: storm,
        thunderPlayer: thunder,
        appSettings: settings,
      );
      expect(storm.mode, equals('OFF'));
    });
  });
}
