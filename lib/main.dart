import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'audio/sequence_engine.dart';
import 'audio/thunder_player.dart';
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
  final thunder = ThunderPlayer();
  await thunder.load();

  runApp(StromSyncApp(
    settings: settings,
    presets: presets,
    thunder: thunder,
  ));
}

class StromSyncApp extends StatelessWidget {
  const StromSyncApp({
    super.key,
    required this.settings,
    required this.presets,
    required this.thunder,
  });

  final AppSettings settings;
  final PresetRepository presets;
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
        ChangeNotifierProvider<SequenceEngine>(create: (_) => SequenceEngine()),
        Provider<ThunderPlayer>.value(value: thunder),
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
///
/// A dropped link keeps the control screen on screen: the service reconnects
/// on its own and the status bar says what is happening, so a brief drop does
/// not throw the user back to the start.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final hasSession = context.select<StormService, bool>((s) => s.hasSession);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: hasSession
          ? const ControlScreen(key: ValueKey('control'))
          : const ConnectScreen(key: ValueKey('connect')),
    );
  }
}
