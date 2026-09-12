// Initializing formals are not usable for this class's dependencies: a named
// parameter written `this._connection` compiles, but the underscore makes it
// uncallable, so the fields have to be assigned in the initializer list.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../audio/rain_player.dart';
import '../audio/thunder_envelope.dart';
import '../audio/thunder_player.dart';
import '../model/app_settings.dart';
import '../sp621e/sp621e_fleet.dart';
import '../sp621e/sp621e_effects.dart';
import 'bolt_segments.dart';
import 'strike_plan.dart';
import 'strike_planner.dart';
import 'strip_calibration.dart';
import 'thunder_preset.dart';

/// What the last strike actually managed, as opposed to what it was asked to
/// do. The link is slow enough that the difference matters, so it is reported
/// rather than hidden.
@immutable
class StrikeReport {
  const StrikeReport({
    required this.presetName,
    required this.planned,
    required this.executed,
    required this.dropped,
    required this.worstLateMs,
    required this.wallClock,
  });

  final String presetName;
  final int planned;
  final int executed;
  final int dropped;

  /// How far behind schedule the worst step ran.
  final int worstLateMs;

  /// How long the strike really took, against the plan's own estimate.
  final Duration wallClock;

  bool get keptTime => dropped == 0 && worstLateMs < 80;

  @override
  String toString() => '$presetName: $executed/$planned steps, '
      '$dropped dropped, worst ${worstLateMs}ms late';
}

/// The standing weather between strikes.
enum Ambience {
  /// Strip dark.
  off('Off'),

  /// A steady storm glow, no sound.
  glow('Glow'),

  /// Rain looping, with the strip breathing gently in the glow colour.
  rain('Rain');

  const Ambience(this.label);

  final String label;
}

/// Runs thunder strikes: plans them, writes them to the controller against a
/// monotonic clock, and starts the sound so it lands when it should. Also owns
/// the rain ambience the strikes happen over.
class ThunderEngine extends ChangeNotifier {
  ThunderEngine({
    required Sp621eFleet connection,
    required ThunderPlayer player,
    required RainPlayer rain,
    required AppSettings settings,
    required StripCalibrationStore calibration,
    required BoltSegmentStore bolts,
    required ThunderEnvelopeStore envelopes,
    Random? random,
  })  : _connection = connection,
        _player = player,
        _rain = rain,
        _settings = settings,
        _calibration = calibration,
        _bolts = bolts,
        _envelopes = envelopes,
        _random = random ?? Random(),
        _plannerSeed = random;

  final Sp621eFleet _connection;
  final ThunderPlayer _player;
  final RainPlayer _rain;
  final AppSettings _settings;
  final StripCalibrationStore _calibration;
  final BoltSegmentStore _bolts;
  final ThunderEnvelopeStore _envelopes;
  final Random? _plannerSeed;
  final Random _random;

  /// Built fresh for each plan so it always carries the link's current
  /// measured write cost, which changes as the connection interval settles.
  StrikePlanner get _planner => StrikePlanner(
        random: _plannerSeed,
        writeCostMs: _connection.measuredWriteMs,
      );

  /// What one BLE write is currently costing, surfaced so the UI can explain
  /// why a strike is as slow as it is.
  int get measuredWriteMs => _connection.measuredWriteMs;

  /// A step running this far behind schedule has missed its moment, and
  /// writing it would only push everything after it further out.
  static const int lateToleranceMs = 45;

  bool _striking = false;
  bool get isStriking => _striking;

  bool _stormMode = false;
  bool get stormMode => _stormMode;

  Timer? _stormTimer;
  Timer? _breathTimer;
  bool _cancelled = false;

  StrikeReport? _lastReport;
  StrikeReport? get lastReport => _lastReport;

  StrikePlan? _lastPlan;
  StrikePlan? get lastPlan => _lastPlan;

  // -------------------------------------------------------------------
  // Ambience
  // -------------------------------------------------------------------

  Ambience _ambience = Ambience.glow;
  Ambience get ambience => _ambience;

  /// Deep storm blue. A saturated cyan reads as decoration; an overcast sky
  /// lit from within is a dim, desaturated blue, and keeping it dark is what
  /// leaves the strike somewhere to jump to.
  int _glowR = 24;
  int _glowG = 48;
  int _glowB = 96;

  (int, int, int) get glowColor => (_glowR, _glowG, _glowB);

  void setGlowColor(int r, int g, int b) {
    _glowR = r;
    _glowG = g;
    _glowB = b;
    notifyListeners();
    if (!_striking) unawaited(_settle());
  }

  int _glowBrightness = 26;
  int get glowBrightness => _glowBrightness;
  set glowBrightness(int value) {
    final clamped = value.clamp(1, 160).toInt();
    if (_glowBrightness == clamped) return;
    _glowBrightness = clamped;
    notifyListeners();
    if (!_striking) unawaited(_settle());
  }

  /// How far the rain glow breathes above and below [glowBrightness].
  int breathDepth = 14;

  Future<void> setAmbience(Ambience next) async {
    if (_ambience == next) return;
    _ambience = next;
    notifyListeners();

    _breathTimer?.cancel();
    _breathTimer = null;

    if (next == Ambience.rain) {
      await _rain.start();
      _startBreathing();
    } else {
      await _rain.stop();
    }

    if (!_striking) await _settle();
  }

  /// Drives the slow brightness wander that makes the rain glow look alive.
  ///
  /// Deliberately slow: one write every three quarters of a second is about
  /// 1.3 writes per second, which leaves the link almost entirely free for
  /// whatever strike lands next.
  void _startBreathing() {
    var phase = 0.0;

    _breathTimer = Timer.periodic(
      const Duration(milliseconds: 750),
      (_) async {
        if (_ambience != Ambience.rain) return;
        if (_striking || !_connection.isConnected) return;

        phase += 0.35;
        final wobble = sin(phase) * breathDepth;
        final level = (_glowBrightness + wobble).round().clamp(1, 255);

        await _connection.setColor(_glowR, _glowG, _glowB, level: level);
      },
    );
  }

  /// Shortest and longest gap between automatic strikes in storm mode.
  int stormMinSeconds = 6;
  int stormMaxSeconds = 25;

  // -------------------------------------------------------------------
  // Planning
  // -------------------------------------------------------------------

  /// Builds a plan without running it, for the timeline preview.
  StrikePlan preview(ThunderPreset preset) => _planFor(preset);

  /// Chooses between a scripted strike and one driven by the recording.
  ///
  /// Falls back to the scripted planner when the sample has not been analysed,
  /// so turning the option on before analysis finishes degrades quietly rather
  /// than producing nothing.
  StrikePlan _planFor(ThunderPreset preset) {
    final planner = _planner;

    if (preset.placement.followSound) {
      final envelope = _envelopes.forDistance(preset.sound.distance);
      if (envelope != null && !envelope.isEmpty) {
        return planner.buildFromEnvelope(
          preset,
          _calibration.value,
          envelope,
          bolts: _bolts.segments,
          speakerLatencyMs: _settings.speakerLatencyMs,
        );
      }
    }

    return planner.build(
      preset,
      _calibration.value,
      bolts: _bolts.segments,
    );
  }

  // -------------------------------------------------------------------
  // Striking
  // -------------------------------------------------------------------

  /// Fires a strike with nothing to configure.
  ///
  /// Picks a random stretch of 30-50 LEDs and a random distance, flares that
  /// stretch in time with the recording, and drops back to the standing glow.
  Future<StrikeReport?> autoStrike() async {
    if (!_connection.isConnected) return null;
    if (_striking) return null;

    final distance = ThunderDistance
        .values[_random.nextInt(ThunderDistance.values.length)];

    final sound = ThunderSound(
      distance: distance,
      // Near strikes are sharper and brighter than distant ones.
      sharpness: switch (distance) {
        ThunderDistance.close => 0.9,
        ThunderDistance.mid => 0.55,
        ThunderDistance.far => 0.2,
      },
      energy: switch (distance) {
        ThunderDistance.close => 1.0,
        ThunderDistance.mid => 0.8,
        ThunderDistance.far => 0.55,
      },
      rumbleTailMs: 0,
      warmth: switch (distance) {
        ThunderDistance.close => 2,
        ThunderDistance.mid => 16,
        ThunderDistance.far => 32,
      },
    );

    final plan = _planner.buildAutoStrike(
      sound,
      _calibration.value,
      _envelopes.forDistance(distance),
      minSegment: minSegmentLeds,
      maxSegment: maxSegmentLeds,
      speakerLatencyMs: _settings.speakerLatencyMs,
    );

    return run(plan, sample: plan.sample);
  }

  /// How much of the strip one bolt lights.
  int minSegmentLeds = 30;
  int maxSegmentLeds = 50;

  Future<StrikeReport?> strike(ThunderPreset preset) async {
    if (!_connection.isConnected) return null;
    if (_striking) return null;

    final plan = _planFor(preset);
    return run(plan, sample: plan.sample);
  }

  /// Executes [plan]. Exposed directly so the calibration screen can drive a
  /// bare sweep through the same path the strikes use.
  Future<StrikeReport?> run(StrikePlan plan, {ThunderDistance? sample}) async {
    if (!_connection.isConnected) return null;
    if (_striking) return null;

    _striking = true;
    _cancelled = false;
    _lastPlan = plan;
    notifyListeners();

    // The shadow state is deliberately kept here. Discarding it forces every
    // command to be re-sent, and at real measured write costs those redundant
    // writes are the difference between a strike that lands and one that drags.
    // Nothing else writes to this controller while the app holds the link.
    _connection.resetWriteStats();

    var executed = 0;
    var dropped = 0;
    var worstLate = 0;

    final clock = Stopwatch();

    try {
      // Power on BEFORE the clock starts. This write can take a hundred
      // milliseconds or more, and charging that to the plan would make the
      // opening steps late enough to be dropped — which is exactly what
      // removes the travelling bolt and leaves only the flashes.
      await _connection.setPower(true);
      await _connection.flush();

      clock.start();

      // The sound is timed from the main stroke, then pulled forward by
      // however long the speaker itself lags.
      if (sample != null) {
        final delay = plan.mainStrokeAt +
            plan.thunderDelay -
            Duration(milliseconds: _settings.speakerLatencyMs);
        _player.playAfter(
          sample,
          delay.isNegative ? Duration.zero : delay,
          from: plan.audioSeek,
        );
      }

      for (var i = 0; i < plan.steps.length; i++) {
        if (_cancelled) break;

        final step = plan.steps[i];
        final isLast = i == plan.steps.length - 1;
        final wait = step.at - clock.elapsed;

        if (wait > Duration.zero) {
          await Future<void>.delayed(wait);
        } else {
          final late = -wait.inMilliseconds;
          if (late > worstLate) worstLate = late;

          // The final step puts the strip back to a known state, so it is
          // never dropped no matter how far behind the run has fallen.
          if (late > lateToleranceMs && !isLast) {
            dropped++;
            continue;
          }
        }

        if (_cancelled) break;
        await _apply(step);
        executed++;
      }
    } finally {
      clock.stop();
      if (!_cancelled) await _settle();

      _striking = false;
      _lastReport = StrikeReport(
        presetName: plan.presetName,
        planned: plan.steps.length,
        executed: executed,
        dropped: dropped,
        worstLateMs: worstLate,
        wallClock: clock.elapsed,
      );
      notifyListeners();
    }

    return _lastReport;
  }

  Future<void> _apply(StrikeStep step) async {
    switch (step) {
      case SweepStep():
        // Only the addressable controllers act on this. The rest of the fleet
        // stays in step through the brightness and colour steps around it.
        await _connection.setSegment(
          effect: step.effect,
          speed: step.speed,
          length: step.length,
          brightness: step.brightness,
        );
        await _connection.setBrightness(step.brightness);

      case FloodStep():
        await _connection.setColor(
          step.r,
          step.g,
          step.b,
          level: step.brightness,
        );

      case FlickerStep():
        // Brightness only. Touching anything else here is what makes a
        // flicker look like a slideshow.
        await _connection.setBrightness(step.brightness);

      case DarkStep():
        await _connection.setBrightness(0);
    }
  }

  /// Returns the strip to whatever it should look like between strikes.
  Future<void> _settle() async {
    if (!_connection.isConnected) return;

    switch (_ambience) {
      case Ambience.off:
        await _connection.setBrightness(0);

      case Ambience.glow:
      case Ambience.rain:
        await _connection.setColor(
          _glowR,
          _glowG,
          _glowB,
          level: _glowBrightness,
        );
    }
  }

  /// Flashes one bolt repeatedly, so its pixel range can be checked against
  /// the real strip.
  ///
  /// The controller gives no way to park a moving effect: once a sweep starts,
  /// the block keeps travelling. So this cannot hold a bolt lit. What it does
  /// instead is run the same sweep-and-cut a strike uses, several times over —
  /// the last thing visible before each blackout is the block sitting on the
  /// bolt, and repeating it makes that position easy to read.
  Future<void> locateBolt(BoltSegment bolt, {int repeats = 4}) async {
    if (!_connection.isConnected || _striking) return;

    _striking = true;
    notifyListeners();

    try {
      const speed = 6;
      final dwell = _calibration.value.dwellForPosition(
        bolt.positionIn(_calibration.value),
        speed,
      );

      await _connection.setPower(true);

      for (var i = 0; i < repeats; i++) {
        // Re-selecting the effect restarts the block at the strip's origin,
        // which is what makes the dwell mean the same thing every time.
        _connection.invalidateShadow();

        await _connection.setSegment(
          effect: Sp621eEffects.whiteSegmentSpin,
          speed: speed,
          length: bolt.length,
          brightness: 255,
        );
        await _connection.flush();

        await Future<void>.delayed(dwell);

        await _connection.setBrightness(0);
        await _connection.flush();

        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    } finally {
      _striking = false;
      await _settle();
      notifyListeners();
    }
  }

  /// Stops the strike in progress and puts the strip back.
  Future<void> cancel() async {
    _cancelled = true;
    await _player.stopAll();
    await _settle();
  }

  // -------------------------------------------------------------------
  // Storm mode
  // -------------------------------------------------------------------

  void setStormMode(bool enabled) {
    if (_stormMode == enabled) return;
    _stormMode = enabled;
    notifyListeners();

    if (!enabled) {
      _stormTimer?.cancel();
      _stormTimer = null;
      unawaited(cancel());
      return;
    }

    unawaited(_stormTick());
  }

  Future<void> _stormTick() async {
    if (!_stormMode) return;

    if (_connection.isConnected) {
      await autoStrike();
    }

    if (!_stormMode) return;

    final span = max(1, stormMaxSeconds - stormMinSeconds);
    final gap = stormMinSeconds + _random.nextInt(span);

    _stormTimer?.cancel();
    _stormTimer = Timer(Duration(seconds: gap), () => unawaited(_stormTick()));
  }

  @override
  void dispose() {
    _stormTimer?.cancel();
    _breathTimer?.cancel();
    super.dispose();
  }
}
