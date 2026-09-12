import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/sp621e_ble_service.dart';
import '../models/led_controller_state.dart';
import '../audio/thunder_player.dart';
import '../lightning/lightning_engine.dart';

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final ThunderPlayer _thunderPlayer = ThunderPlayer();
  LightningProfile _selectedProfile = LightningProfile.normal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<Sp621eBleService>().scan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bleService = context.watch<Sp621eBleService>();
    final state = bleService.state;
    final thunderPlayer = context.read<ThunderPlayer>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('SP621E Controller'),
        actions: [
          if (state.connectionState == Sp621eConnectionState.connected)
            IconButton(
              icon: const Icon(Icons.link_off),
              onPressed: () => bleService.disconnect(),
            ),
        ],
      ),
      body: state.connectionState != Sp621eConnectionState.connected
          ? _buildConnectView(bleService)
          : _buildControlView(bleService, state, thunderPlayer),
    );
  }

  Widget _buildConnectView(Sp621eBleService bleService) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (bleService.state.connectionState == Sp621eConnectionState.scanning)
            const CircularProgressIndicator()
          else if (bleService.state.connectionState == Sp621eConnectionState.connecting)
            const Text('Connecting...')
          else
            ElevatedButton(
              onPressed: () => bleService.scan(),
              child: const Text('Scan & Connect'),
            ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: bleService.discoveredDevices.length,
              itemBuilder: (context, index) {
                final device = bleService.discoveredDevices[index];
                return ListTile(
                  title: Text(device.platformName.isNotEmpty ? device.platformName : 'Unknown Device'),
                  subtitle: Text(device.remoteId.str),
                  onTap: () => bleService.connect(device.remoteId.str),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlView(Sp621eBleService bleService, Sp621eControllerState state, ThunderPlayer thunderPlayer) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        SwitchListTile(
          title: const Text('Power'),
          value: state.isOn,
          onChanged: (value) {
            if (value) {
              bleService.powerOn();
            } else {
              bleService.powerOff();
            }
          },
        ),
        const Divider(),
        const Text('Brightness'),
        Slider(
          value: state.brightness.toDouble(),
          min: 0,
          max: 255,
          onChanged: (value) {
            bleService.setBrightness(value.toInt());
          },
        ),
        const Divider(),
        const Text('Colors'),
        Wrap(
          spacing: 8,
          children: [
            ElevatedButton(
              onPressed: () => bleService.setColor(255, 0, 0),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Red', style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              onPressed: () => bleService.setColor(0, 255, 0),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Green', style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              onPressed: () => bleService.setColor(0, 0, 255),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('Blue', style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              onPressed: () => bleService.setColor(255, 255, 255),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200]),
              child: const Text('White', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
        const Divider(),
        const Text('Effects (Speed)'),
        Slider(
          value: state.effectSpeed.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          onChanged: (value) {
            bleService.setEffectSpeed(value.toInt());
          },
        ),
        const SizedBox(height: 8),
        const Text('Effect Length'),
        Slider(
          value: state.effectLength.toDouble(),
          min: 1,
          max: 150,
          divisions: 149,
          onChanged: (value) {
            bleService.setEffectLength(value.toInt());
          },
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Built-in Hardware Effect:'),
            Text('${state.effect}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        Slider(
          value: state.effect.toDouble().clamp(0, 255),
          min: 0,
          max: 255,
          divisions: 255,
          label: state.effect.toString(),
          activeColor: Colors.purple,
          onChanged: (value) {
            // Update UI immediately while sliding
            bleService.setEffect(value.toInt());
          },
        ),
        const Text(
          'Tip: Slide through the effects (1-150) to find one that looks exactly like a moving lightning strike! Let me know if you find a good number.',
          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 12),
        ),
        const Divider(),
        SwitchListTile(
          title: const Text('Continuous Storm Mode', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Periodically triggers random lightning strikes'),
          value: state.isStormMode,
          activeTrackColor: Colors.amber,
          onChanged: (value) {
            bleService.toggleStormMode(thunderPlayer, value);
          },
        ),
        const SizedBox(height: 16),
        const Text('Lightning Profile', style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButton<LightningProfile>(
          value: _selectedProfile,
          isExpanded: true,
          items: LightningProfile.values.map((profile) {
            return DropdownMenuItem(
              value: profile,
              child: Text(profile.name.toUpperCase()),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedProfile = value;
              });
            }
          },
        ),
        const SizedBox(height: 16),
        const Text('Manual Strikes', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton.icon(
            onPressed: state.isStormMode 
                ? null 
                : () => bleService.triggerThunder(thunderPlayer, profile: _selectedProfile),
            icon: const Icon(Icons.flash_on, size: 28),
            label: const Text('TRIGGER LIGHTNING', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              disabledBackgroundColor: Colors.grey[800],
              disabledForegroundColor: Colors.grey[500],
            ),
          ),
        ),
        const Divider(height: 48),
        const Text(
          'Protocol Fuzzer (Find which one works!)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: List.generate(12, (index) {
            final protocolNumber = index + 1;
            return ElevatedButton(
              onPressed: () => bleService.testProtocol(protocolNumber),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
              ),
              child: Text('Test $protocolNumber'),
            );
          }),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStrikeButton(
    String label,
    LightningProfile profile,
    Sp621eBleService bleService,
    ThunderPlayer thunderPlayer,
  ) {
    return ElevatedButton.icon(
      onPressed: bleService.state.isStormMode 
          ? null 
          : () => bleService.triggerThunder(thunderPlayer, profile: profile),
      icon: const Icon(Icons.flash_on, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.amber,
        foregroundColor: Colors.black,
        disabledBackgroundColor: Colors.grey[800],
        disabledForegroundColor: Colors.grey[500],
      ),
    );
  }
}

