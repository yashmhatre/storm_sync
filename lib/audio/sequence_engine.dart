import 'dart:async';
import 'package:flutter/foundation.dart';

import '../ble/storm_service.dart';
import '../model/app_settings.dart';
import '../model/storm_sequence.dart';
import 'thunder_player.dart';

enum SequenceStatus {
  idle,
  running,
  completed,
}

/// Coordinates async timing, command dispatch, and audio playback for [StormSequence]s.
class SequenceEngine extends ChangeNotifier {
  SequenceEngine();

  SequenceStatus _status = SequenceStatus.idle;
  StormSequence? _currentSequence;
  int _currentStepIndex = -1;
  Timer? _activeStepTimer;
  int _iteration = 0;

  bool get isRunning => _status == SequenceStatus.running;
  SequenceStatus get status => _status;
  StormSequence? get currentSequence => _currentSequence;
  int get currentStepIndex => _currentStepIndex;
  int get iteration => _iteration;

  /// Progress through the current sequence (0.0 to 1.0).
  double get progress {
    final seq = _currentSequence;
    if (seq == null || seq.steps.isEmpty || _currentStepIndex < 0) return 0.0;
    if (_status == SequenceStatus.completed) return 1.0;
    return ((_currentStepIndex + 1) / seq.steps.length).clamp(0.0, 1.0);
  }

  /// Begins playing [sequence].
  void start({
    required StormSequence sequence,
    required StormService stormService,
    required ThunderPlayer thunderPlayer,
    required AppSettings appSettings,
  }) {
    if (sequence.steps.isEmpty) return;
    stop();

    _status = SequenceStatus.running;
    _currentSequence = sequence;
    _currentStepIndex = 0;
    _iteration = 1;
    notifyListeners();

    _scheduleStep(
      stepIndex: 0,
      stormService: stormService,
      thunderPlayer: thunderPlayer,
      appSettings: appSettings,
    );
  }

  void _scheduleStep({
    required int stepIndex,
    required StormService stormService,
    required ThunderPlayer thunderPlayer,
    required AppSettings appSettings,
  }) {
    if (!isRunning) return;
    final seq = _currentSequence;
    if (seq == null) return;

    final step = seq.steps[stepIndex];
    final delay = Duration(milliseconds: step.delayBeforeMs);

    _activeStepTimer?.cancel();
    _activeStepTimer = Timer(delay, () {
      if (!isRunning) return;

      _currentStepIndex = stepIndex;
      notifyListeners();

      // Dispatch optional custom color override
      if (step.boltColor != null) {
        stormService.setColor(
          step.boltColor!.r,
          step.boltColor!.g,
          step.boltColor!.b,
          finalValue: true,
        );
      }
      if (step.tintColor != null) {
        stormService.setTint(
          step.tintColor!.r,
          step.tintColor!.g,
          step.tintColor!.b,
          finalValue: true,
        );
      }

      // Dispatch BLE command
      stormService.send(step.command);

      // Dispatch synchronized thunder audio if specified
      if (step.distance != null) {
        final audioDelay = appSettings.audioDelayFor(step.distance!.distanceDelayMs);
        thunderPlayer.playAfter(step.distance!, audioDelay);
      }

      // If more steps remain in sequence
      if (stepIndex + 1 < seq.steps.length) {
        _scheduleStep(
          stepIndex: stepIndex + 1,
          stormService: stormService,
          thunderPlayer: thunderPlayer,
          appSettings: appSettings,
        );
      } else if (seq.isLooping) {
        // Loop back to beginning
        _iteration++;
        _scheduleStep(
          stepIndex: 0,
          stormService: stormService,
          thunderPlayer: thunderPlayer,
          appSettings: appSettings,
        );
      } else {
        // Completed
        _status = SequenceStatus.completed;
        _activeStepTimer = null;
        notifyListeners();
      }
    });
  }

  /// Halts the current sequence immediately.
  void stop() {
    _activeStepTimer?.cancel();
    _activeStepTimer = null;
    final wasActive = _status != SequenceStatus.idle;
    _status = SequenceStatus.idle;
    _currentStepIndex = -1;
    if (wasActive) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

