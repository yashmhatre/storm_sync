import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'audio/sequence_engine.dart';
import 'audio/sound_pack.dart';
import 'audio/thunder_player.dart';
import 'ble/background_service.dart';
import 'ble/storm_service.dart';
import 'model/app_settings.dart';
import 'model/preset_repository.dart';
import 'ui/connect_screen.dart';
import 'ui/control_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persistent configurations before first frame
  final settings = await AppSettings.load();
  final presets = await PresetRepository.load();
  final soundPacks = await SoundPackManager.load();
  final bgRemote = BackgroundRemoteService();
  await bgRemote.initialize();

  final thunder = ThunderPlayer();
  await thunder.loadPack(soundPacks.activePack);

  runApp(StromSyncApp(
    settings: settings,
    presets: presets,
    soundPacks: soundPacks,
    bgRemote: bgRemote,
    thunder: thunder,
  ));
}

class StromSyncApp extends StatelessWidget {
  const StromSyncApp({
    super.key,
    required this.settings,
    required this.presets,
    required this.soundPacks,
    required this.bgRemote,
    required this.thunder,
  });

  final AppSettings settings;
  final PresetRepository presets;
  final SoundPackManager soundPacks;
  final BackgroundRemoteService bgRemote;
  final ThunderPlayer thunder;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<StormService>(
          create: (_) => StormService()..start(),
        ),
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<PresetRepository>.value(value: presets),
        ChangeNotifierProvider<SoundPackManager>.value(value: soundPacks),
        ChangeNotifierProvider<SequenceEngine>(create: (_) => SequenceEngine()),
        ChangeNotifierProvider<ThunderPlayer>.value(value: thunder),
        Provider<BackgroundRemoteService>.value(value: bgRemote),
      ],
      child: MaterialApp(
        title: 'StromSync',
        debugShowCheckedModeBanner: false,
        theme: buildStormTheme(),
        home: const _Root(),
      ),
    );
  }
}

/// Shows the connect screen until the link is up, then the controls.
/// Maintains lock screen / notification actions for background controls.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bg = context.read<BackgroundRemoteService>();
      bg.initialize(
        onActionSelected: (action) {
          if (!mounted) return;
          final storm = context.read<StormService>();
          final thunder = context.read<ThunderPlayer>();
          final settings = context.read<AppSettings>();
          bg.dispatchAction(
            action: action,
            stormService: storm,
            thunderPlayer: thunder,
            appSettings: settings,
          );
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final storm = context.watch<StormService>();
    final bg = context.read<BackgroundRemoteService>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      bg.updateNotification(
        isConnected: storm.isConnected,
        mode: storm.mode,
        statusText: storm.status,
      );
    });

    final hasSession = storm.hasSession;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: hasSession
          ? const ControlScreen(key: ValueKey('control'))
          : const ConnectScreen(key: ValueKey('connect')),
    );
  }
}
