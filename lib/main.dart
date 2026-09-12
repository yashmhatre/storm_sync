import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'audio/rain_player.dart';
import 'audio/sound_pack.dart';
import 'audio/thunder_envelope.dart';
import 'audio/thunder_player.dart';
import 'model/app_settings.dart';
import 'sp621e/sp621e_connection.dart';
import 'sp621e/sp621e_fleet.dart';
import 'thunder/bolt_segments.dart';
import 'thunder/strip_calibration.dart';
import 'thunder/thunder_engine.dart';
import 'thunder/thunder_preset.dart';
import 'ui/theme.dart';
import 'ui/thunder/connect_screen.dart';
import 'ui/thunder/thunder_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Everything persisted loads before the first frame, so no screen ever has
  // to render a placeholder for settings that are already on disk.
  final settings = await AppSettings.load();
  final soundPacks = await SoundPackManager.load();
  final calibration = await StripCalibrationStore.load();
  final presets = await ThunderPresetStore.load();
  final bolts = await BoltSegmentStore.load();

  final thunder = ThunderPlayer();
  await thunder.loadPack(soundPacks.activePack);

  // Decoded up front so the first rain toggle is instant, and so a missing
  // sample is known about before any screen offers the option.
  final rain = RainPlayer();
  await rain.load();

  // Analysing the samples takes a moment and nothing depends on it at startup,
  // so it runs in the background; presets that follow the sound fall back to
  // the scripted planner until it lands.
  final envelopes = ThunderEnvelopeStore();
  unawaited(envelopes.analyseAll());

  runApp(
    ThunderApp(
      settings: settings,
      soundPacks: soundPacks,
      calibration: calibration,
      presets: presets,
      bolts: bolts,
      envelopes: envelopes,
      thunder: thunder,
      rain: rain,
    ),
  );
}

/// A thunder box for an SP621E: it fires lightning across the strip and plays
/// the clap so it lands when it should. It is not a general LED remote.
class ThunderApp extends StatelessWidget {
  const ThunderApp({
    super.key,
    required this.settings,
    required this.soundPacks,
    required this.calibration,
    required this.presets,
    required this.bolts,
    required this.envelopes,
    required this.thunder,
    required this.rain,
  });

  final AppSettings settings;
  final SoundPackManager soundPacks;
  final StripCalibrationStore calibration;
  final ThunderPresetStore presets;
  final BoltSegmentStore bolts;
  final ThunderEnvelopeStore envelopes;
  final ThunderPlayer thunder;
  final RainPlayer rain;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<SoundPackManager>.value(value: soundPacks),
        ChangeNotifierProvider<StripCalibrationStore>.value(value: calibration),
        ChangeNotifierProvider<ThunderPresetStore>.value(value: presets),
        ChangeNotifierProvider<BoltSegmentStore>.value(value: bolts),
        ChangeNotifierProvider<ThunderEnvelopeStore>.value(value: envelopes),
        ChangeNotifierProvider<ThunderPlayer>.value(value: thunder),
        ChangeNotifierProvider<RainPlayer>.value(value: rain),
        ChangeNotifierProvider<Sp621eFleet>(create: (_) => Sp621eFleet()),
        // Screens that scan or report on one controller use the first slot;
        // everything that drives light uses the fleet.
        ProxyProvider<Sp621eFleet, Sp621eConnection>(
          update: (_, fleet, _) => fleet.primary,
        ),
        // The engine needs the live connection, so it is built from the
        // provider above rather than in main(). It holds that connection for
        // its lifetime, so there is nothing for a proxy provider to update.
        ChangeNotifierProvider<ThunderEngine>(
          create: (context) => ThunderEngine(
            connection: context.read<Sp621eFleet>(),
            player: thunder,
            rain: rain,
            settings: settings,
            calibration: calibration,
            bolts: bolts,
            envelopes: envelopes,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Thunder',
        debugShowCheckedModeBanner: false,
        theme: buildStormTheme(),
        home: const _Root(),
      ),
    );
  }
}

/// Connect screen until the controller is on the line, then the thunder
/// controls.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final connected = context.select<Sp621eFleet, bool>(
      (f) => f.isConnected,
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: connected
          ? const ThunderHome(key: ValueKey('home'))
          : const ThunderConnectScreen(key: ValueKey('connect')),
    );
  }
}
