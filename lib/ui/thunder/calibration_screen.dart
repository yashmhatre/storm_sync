import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../sp621e/banlanx2_protocol.dart';
import '../../sp621e/sp621e_connection.dart';
import '../../sp621e/sp621e_effects.dart';
import '../../thunder/strike_planner.dart';
import '../../thunder/strip_calibration.dart';
import '../../thunder/thunder_engine.dart';

/// Measures how long the controller's sweep takes to cross the strip.
///
/// Placement is open-loop: nothing on the controller reports where its lit
/// block has reached, so the only way to turn "60% along the strip" into a
/// dwell time is to time one lap by hand. This screen does that, once.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const int _speed = 4;

  final Stopwatch _clock = Stopwatch();
  bool _running = false;
  int _pixelCount = 288;
  bool _pixelsLoaded = false;

  /// Redraws the elapsed readout while a measurement is running.
  Timer? _ticker;

  /// Held rather than read from the context, because the strip has to be put
  /// out during dispose, when the element is no longer safe to look up.
  Sp621eConnection? _connection;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _connection = context.read<Sp621eConnection>();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // Leave the strip dark rather than spinning a calibration sweep forever.
    final connection = _connection;
    if (connection != null && connection.isConnected) {
      connection.setBrightness(0);
    }
    super.dispose();
  }

  Future<void> _start() async {
    final connection = context.read<Sp621eConnection>();
    if (!connection.isConnected) return;

    await connection.setPower(true);
    await connection.setEffect(Sp621eEffects.whiteSegmentSpin);
    await connection.setSpeed(_speed);
    // A narrow block makes the moment it passes the end unambiguous.
    await connection.setLength(8);
    await connection.setBrightness(255);

    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) {
        if (mounted && _running) setState(() {});
      },
    );

    setState(() {
      _clock
        ..reset()
        ..start();
      _running = true;
    });
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    _ticker = null;
    _clock.stop();
    final observed = _clock.elapsed;

    final store = context.read<StripCalibrationStore>();
    final connection = context.read<Sp621eConnection>();

    store.value = store.value
        .calibrate(speed: _speed, observed: observed)
        .copyWith(pixelCount: _pixelCount);

    if (connection.isConnected) await connection.setBrightness(0);

    if (!mounted) return;
    setState(() => _running = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Measured ${observed.inMilliseconds} ms per lap at speed $_speed',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StripCalibrationStore>();
    final connection = context.watch<Sp621eConnection>();
    final calibration = store.value;

    if (!_pixelsLoaded) {
      _pixelCount = calibration.pixelCount;
      _pixelsLoaded = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Calibrate strip')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Why this is needed',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'The SP621E cannot light a chosen range of LEDs, and it never '
            'reports where its moving block has got to. A bolt is placed by '
            'running a sweep for a measured time and then cutting to black, so '
            'the app needs to know how fast that block travels on your strip.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Measure',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Press Start, watch the white block, and press Stop the '
                    'moment it reaches the far end of the strip.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _running
                          ? '${_clock.elapsed.inMilliseconds} ms'
                          : '${calibration.traverseMs(_speed)} ms',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!connection.isConnected)
                    const Text('Not connected.')
                  else if (_running)
                    FilledButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop — it reached the end'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start sweep'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Strip length',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Only used to label positions in LEDs. It does not change '
                    'what is sent to the controller.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _pixelCount.toDouble().clamp(30, 1000),
                          min: 30,
                          max: 1000,
                          onChanged: (v) =>
                              setState(() => _pixelCount = v.round()),
                          onChangeEnd: (v) => store.value = store.value
                              .copyWith(pixelCount: v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text('$_pixelCount', textAlign: TextAlign.end),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Colour order',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap each button and check the strip really shows that '
                    'colour. If red comes out green, the order is wrong and '
                    'every colour in the app will be wrong with it, lightning '
                    'included.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final test in const [
                        ('Red', 255, 0, 0),
                        ('Green', 0, 255, 0),
                        ('Blue', 0, 0, 255),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: OutlinedButton(
                            onPressed: connection.isConnected
                                ? () async {
                                    await connection.setPower(true);
                                    await connection.setColor(
                                      test.$2,
                                      test.$3,
                                      test.$4,
                                      level: 200,
                                    );
                                  }
                                : null,
                            child: Text(test.$1),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var i = 0; i < BanlanX2.chipOrders.length; i++)
                        ChoiceChip(
                          label: Text(BanlanX2.chipOrders[i]),
                          selected: connection.chipOrder == i,
                          onSelected: connection.isConnected
                              ? (_) => connection.setChipOrder(i)
                              : null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What this gives you',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 10),
                  for (final speed in [2, 4, 6, 8, 10])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 74,
                            child: Text('Speed $speed'),
                          ),
                          Expanded(
                            child: Text(
                              '${calibration.traverseMs(speed)} ms per lap',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          Text(
                            'nearest '
                            '${(StrikePlanner.minimumPlacement(speed, calibration, writeCostMs: context.read<ThunderEngine>().measuredWriteMs) * 100).round()}%',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'The last column is how near the start of the strip a bolt '
                    'can be placed at that speed. A sweep cannot be cut short '
                    'faster than its own commands go out.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
