import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../audio/thunder_player.dart';
import '../ble/storm_service.dart';
import 'tabs/colour_tab.dart';
import 'tabs/sequencer_tab.dart';
import 'tabs/storm_tab.dart';
import 'tabs/tuning_tab.dart';
import 'widgets/log_panel.dart';
import 'widgets/preset_sheet.dart';
import 'widgets/status_bar.dart';

/// The main screen once a link exists: three tabs over a persistent status
/// line, with the log docked at the bottom.
class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  bool _logExpanded = false;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<StormService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('StromSync'),
        actions: [
          IconButton(
            tooltip: 'Presets',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const PresetSheet(),
            ),
            icon: const Icon(Icons.bookmark_outline),
          ),
          IconButton(
            tooltip: 'Re-read parameters (LIST)',
            onPressed:
                service.isConnected ? () => service.refreshParameters() : null,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: _logExpanded ? 'Hide log' : 'Show log',
            onPressed: () => setState(() => _logExpanded = !_logExpanded),
            icon: Icon(
              _logExpanded ? Icons.terminal : Icons.terminal_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Disconnect',
            onPressed: () => _disconnect(context),
            icon: const Icon(Icons.link_off),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.thunderstorm_outlined), text: 'Storm'),
            Tab(icon: Icon(Icons.auto_awesome_motion_outlined), text: 'Sequencer'),
            Tab(icon: Icon(Icons.tune), text: 'Tuning'),
            Tab(icon: Icon(Icons.palette_outlined), text: 'Colour'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const StatusBar(),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  StormTab(),
                  SequencerTab(),
                  TuningTab(),
                  ColourTab(),
                ],
              ),
            ),
            LogPanel(
              expanded: _logExpanded,
              onToggle: () => setState(() => _logExpanded = !_logExpanded),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _disconnect(BuildContext context) async {
    final service = context.read<StormService>();
    final thunder = context.read<ThunderPlayer>();

    // Cancel any thunder still queued from a strike, so the room does not
    // rumble after the user has walked away from the light.
    await thunder.stopAll();
    await service.disconnect();
  }
}
