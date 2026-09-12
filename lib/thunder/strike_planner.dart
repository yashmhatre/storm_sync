import 'dart:math';

import '../audio/thunder_envelope.dart';
import '../sp621e/sp621e_effects.dart';
import 'bolt_segments.dart';
import 'strike_plan.dart';
import 'strip_calibration.dart';
import 'thunder_preset.dart';

/// Builds a [StrikePlan] from a preset and the strip calibration.
///
/// Three ideas drive everything here:
///
/// * **The sound shapes the light.** A preset's sharpness and energy decide how
///   many return strokes there are, how abrupt they are, and how long the
///   afterglow lingers, so a distant roll and an overhead crack produce
///   genuinely different timelines rather than the same one at two
///   brightnesses.
///
/// * **Placement is a dwell time.** The controller cannot light a range of
///   pixels, so a bolt is placed by running a sweep for exactly as long as it
///   takes the lit block to reach the wanted position, then cutting to black.
///
/// * **Flicker is brightness alone.** Re-sending a colour or an effect costs
///   writes the link cannot spare inside a stroke. Once the colour is set, the
///   flicker is carried by the master brightness, one write per pulse, which is
///   what lets pulses sit 50ms apart instead of 160ms.
class StrikePlanner {
  StrikePlanner({Random? random, this.writeCostMs = defaultWriteCostMs})
      : _random = random ?? Random();

  final Random _random;

  /// Fallback cost of one acknowledged BLE write, used before the link has
  /// been measured.
  static const int defaultWriteCostMs = 40;

  /// How much of a recording a single strike will follow.
  ///
  /// Thunder samples are often minutes of storm ambience rather than one clap,
  /// and following all of it would turn one strike into a light show lasting as
  /// long as the file. Only the opening of the sample becomes a strike; the
  /// rest is left to play out as sound.
  static const int defaultFollowWindowMs = 9000;

  /// What one acknowledged write really costs on this link. Measured by the
  /// connection and passed in, because it swings from about 30ms on a
  /// high-priority interval to over 120ms on a relaxed one, and the whole
  /// shape of a strike depends on which it is.
  final int writeCostMs;

  /// No step is scheduled closer than this to the one before it, whatever its
  /// write cost says. Two pulses closer than this read as one.
  static const int minStepGapMs = 45;

  /// The closest to the start of the strip a bolt can actually be placed.
  ///
  /// A sweep that changes every parameter costs four writes, so it cannot be
  /// cut short sooner than that traffic takes to go out. Below the position
  /// this returns, asking for a nearer placement changes nothing visible.
  static double minimumPlacement(
    int speed,
    StripCalibration calibration, {
    int writeCostMs = defaultWriteCostMs,
  }) {
    final floorMs = 4 * writeCostMs;
    final total = calibration.traverseMs(speed);
    if (total <= 0) return 0;
    return (floorMs / total).clamp(0.0, 1.0);
  }

  /// Resolves a placement down to the position and block width the sweep will
  /// actually use.
  ///
  /// A preset that targets a bolt takes its geometry from that bolt: the sweep
  /// is cut when the lit block's leading edge reaches the far end of the shape,
  /// and the block is made exactly as long as the shape, so the bolt is lit
  /// along its whole length and nothing past it is.
  ({double position, int width}) resolvePlacement(
    StrikePlacement placement,
    StripCalibration calibration, {
    List<BoltSegment> bolts = const [],
  }) {
    BoltSegment? bolt;

    if (placement.randomBolt && bolts.isNotEmpty) {
      bolt = bolts[_random.nextInt(bolts.length)];
    } else if (placement.boltId != null) {
      for (final candidate in bolts) {
        if (candidate.id == placement.boltId) {
          bolt = candidate;
          break;
        }
      }
    }

    if (bolt == null) {
      return (position: placement.position, width: placement.widthPixels);
    }

    return (
      position: bolt.positionIn(calibration),
      width: bolt.length,
    );
  }

  /// Builds a strike with no configuration: a random stretch of the strip
  /// flares all at once, blinks, and drops back to the standing glow.
  ///
  /// The hard part is that the only way to light part of an SP621E strip is a
  /// moving effect, and a moving effect is visible while it moves — which reads
  /// as LEDs coming on in series, not as a strike.
  ///
  /// The way round it is to **travel in the dark**. The effect is started with
  /// the brightness at zero, so the block crosses the strip invisibly; when it
  /// reaches the chosen stretch the speed drops to a crawl and the brightness
  /// comes up in a single write. The whole segment appears at once, already in
  /// place, which is what a strike looks like.
  ///
  /// The blink pattern comes from the recording, but it is played at the flash
  /// rather than when the sound arrives. That is both what really happens —
  /// the flash reaches you before the thunder — and what keeps the segment from
  /// drifting off its LEDs while it waits.
  StrikePlan buildAutoStrike(
    ThunderSound sound,
    StripCalibration calibration,
    ThunderEnvelope? envelope, {
    int minSegment = 30,
    int maxSegment = 50,
    int travelSpeed = 10,
    int holdSpeed = 1,
    int speakerLatencyMs = 0,
    int flickerWindowMs = 850,
    bool skyWash = true,
  }) {
    final energy = sound.energy.clamp(0.0, 1.0);
    final length =
        minSegment + _random.nextInt(max(1, maxSegment - minSegment + 1));

    // Keep clear of the near end, which cannot be reached before the travel
    // writes have even gone out, and of the far end, where the block wraps.
    final floor = minimumPlacement(travelSpeed, calibration);
    final position =
        (floor + _random.nextDouble() * (0.95 - floor)).clamp(0.0, 1.0);

    final steps = <StrikeStep>[];
    var cursor = Duration.zero;

    void hold(StrikeStep step, int holdMs) {
      steps.add(step);
      final gap = max(minStepGapMs, step.writeCost * writeCostMs);
      cursor += Duration(milliseconds: max(holdMs, gap));
    }

    // ---------------------------------------------------------------
    // Travel, unlit
    // ---------------------------------------------------------------
    hold(
      SweepStep(
        at: cursor,
        label: 'travel unlit to ${(position * 100).round()}%',
        writeCost: 4,
        effect: Sp621eEffects.whiteSegmentSpin,
        speed: travelSpeed,
        length: length,
        brightness: 0,
      ),
      calibration.dwellForPosition(position, travelSpeed).inMilliseconds,
    );

    // Slow the block so it holds over the same LEDs while it blinks. Only the
    // speed changes, so this is one write, and it is still dark.
    hold(
      SweepStep(
        at: cursor,
        label: 'hold segment',
        writeCost: 1,
        effect: Sp621eEffects.whiteSegmentSpin,
        speed: holdSpeed,
        length: length,
        brightness: 0,
      ),
      0,
    );

    // ---------------------------------------------------------------
    // The strike: the whole segment appears in one write
    // ---------------------------------------------------------------
    final mainStrokeAt = cursor;
    final full = (255 * energy).round().clamp(1, 255);

    hold(
      FlickerStep(at: cursor, label: 'strike', brightness: full),
      0,
    );

    // ---------------------------------------------------------------
    // Blink
    // ---------------------------------------------------------------
    final pattern = _blinkPattern(
      envelope,
      windowMs: flickerWindowMs,
      energy: energy,
      sharpness: sound.sharpness.clamp(0.0, 1.0),
    );

    for (final blink in pattern) {
      hold(
        FlickerStep(
          at: cursor,
          label: blink.$2 > 8 ? 'blink' : 'blink off',
          brightness: blink.$2,
        ),
        blink.$1,
      );
    }

    // ---------------------------------------------------------------
    // Sky wash
    //
    // The channel core really is white, which is what the segment shows, but
    // the air and cloud it lights up are blue-white. The solid effect is the
    // only thing on this controller whose colour can be chosen, so the wash is
    // both the sky lighting up and the only blue in the whole strike.
    // ---------------------------------------------------------------
    if (skyWash) {
      final (washR, washG, washB) = sound.strikeColor;

      hold(
        FloodStep(
          at: cursor,
          label: 'sky wash',
          writeCost: 2,
          r: washR,
          g: washG,
          b: washB,
          brightness: (255 * energy * 0.5).round().clamp(1, 255),
        ),
        30,
      );

      hold(
        FlickerStep(
          at: cursor,
          label: 'wash fade',
          brightness: (255 * energy * 0.16).round().clamp(1, 255),
        ),
        70,
      );
    }

    steps.add(DarkStep(at: cursor, label: 'end'));

    return StrikePlan(
      steps: steps,
      mainStrokeAt: mainStrokeAt,
      thunderDelay: Duration(milliseconds: sound.distance.distanceDelayMs),
      sample: sound.distance,
      presetName: '$length LEDs at ${(position * 100).round()}%',
    );
  }

  /// The blink pattern for a strike, as (hold milliseconds, brightness) pairs.
  ///
  /// Shaped like a real flash rather than a square wave. A lightning flash is
  /// two to four **return strokes** down the same channel: each one snaps to
  /// full in effectively no time and then decays, separated by gaps of a few
  /// tens of milliseconds. The first stroke is the brightest and the rest fall
  /// away unevenly.
  ///
  /// The whole thing is over in well under a second. Stretching it out is what
  /// made earlier versions read as a blinking lamp rather than lightning.
  ///
  /// How much detail fits depends on the link: each step is a write, so on a
  /// slow connection the decay is coarser and there are fewer strokes rather
  /// than a flash that runs long.
  List<(int, int)> _blinkPattern(
    ThunderEnvelope? envelope, {
    required int windowMs,
    required double energy,
    required double sharpness,
  }) {
    // A stroke costs one write for the peak plus one per decay step. Keep the
    // whole flash inside the window by trimming detail, not by running over.
    final decaySteps = writeCostMs <= 55 ? 3 : 2;
    final perStroke = (decaySteps + 2) * writeCostMs;
    final affordable = max(1, windowMs ~/ max(perStroke, 1));

    // Sharp, close strikes have more strokes than a distant roll.
    var strokes = 2 + (sharpness * 2).round();
    strokes = min(strokes, min(affordable, 4));

    // A recording with more onsets in its opening suggests a busier flash.
    if (envelope != null && !envelope.isEmpty) {
      final opening = envelope
          .peaks(minGapMs: max(minStepGapMs, writeCostMs))
          .where((p) => p.at <= Duration(milliseconds: windowMs))
          .length;
      if (opening > 0) {
        strokes = min(max(2, min(opening, 4)), affordable);
      }
    }

    final pattern = <(int, int)>[];
    var strokePeak = 1.0;

    for (var stroke = 0; stroke < strokes; stroke++) {
      if (stroke > 0) {
        // The channel is dark between strokes, though not always fully: a
        // little continuing current is what stops it looking like a switch.
        final continuing = _random.nextDouble() < 0.35;
        pattern.add((
          28 + _random.nextInt(55),
          continuing ? (255 * energy * 0.06).round().clamp(1, 255) : 1,
        ));

        // Later strokes are dimmer, but not tidily so.
        strokePeak *= 0.55 + _random.nextDouble() * 0.3;
      }

      // The stroke itself: straight to peak.
      pattern.add((
        14 + _random.nextInt(14),
        (255 * energy * strokePeak).round().clamp(1, 255),
      ));

      // Then the tail.
      var level = strokePeak;
      for (var step = 0; step < decaySteps; step++) {
        level *= 0.42 + _random.nextDouble() * 0.16;
        pattern.add((
          16 + _random.nextInt(20),
          (255 * energy * level).round().clamp(1, 255),
        ));
      }
    }

    return pattern;
  }

  /// Builds a strike whose flashes come from the recording itself.
  ///
  /// The bolt still fires first, because that is the order the real thing
  /// happens in: the flash reaches you before the sound. What changes is
  /// everything after it — instead of an invented flicker pattern, the strip
  /// follows the actual peaks in the sample, so the light and the rumble are
  /// the same event rather than two things running side by side.
  ///
  /// Peaks are thinned to what the link can carry, using the measured write
  /// cost, so a slow connection degrades to the biggest hits rather than
  /// falling behind the audio.
  StrikePlan buildFromEnvelope(
    ThunderPreset preset,
    StripCalibration calibration,
    ThunderEnvelope envelope, {
    List<BoltSegment> bolts = const [],
    int speakerLatencyMs = 0,
    int maxFollowMs = defaultFollowWindowMs,
  }) {
    final sound = preset.sound;
    final placement = preset.placement;
    final energy = sound.energy.clamp(0.0, 1.0);
    final (red, green, blue) = sound.strikeColor;

    final target = resolvePlacement(placement, calibration, bolts: bolts);

    final steps = <StrikeStep>[];
    var cursor = Duration.zero;

    void push(StrikeStep step, int holdMs) {
      steps.add(step);
      final floor = max(minStepGapMs, step.writeCost * writeCostMs);
      cursor += Duration(milliseconds: max(holdMs, floor));
    }

    // The bolt travels to its placement, exactly as in a scripted strike.
    final dwell = calibration.dwellForPosition(
      target.position,
      placement.speed,
    );

    push(
      SweepStep(
        at: cursor,
        label: 'bolt to ${(target.position * 100).round()}%',
        writeCost: 4,
        effect: placement.sweepEffect,
        speed: placement.speed,
        length: target.width,
        brightness: (255 * energy).round().clamp(1, 255),
      ),
      dwell.inMilliseconds,
    );

    final mainStrokeAt = cursor;

    // Establish the strike colour once. Every flash after this is brightness
    // alone, which is the only way to keep up with a busy recording.
    push(
      FloodStep(
        at: cursor,
        label: 'return stroke',
        writeCost: 2,
        r: red,
        g: green,
        b: blue,
        brightness: (255 * energy).round().clamp(1, 255),
      ),
      0,
    );

    // Where the audio starts, relative to the main stroke.
    final audioOffset = Duration(
      milliseconds: max(
        0,
        sound.distance.distanceDelayMs - speakerLatencyMs,
      ),
    );

    // Flashes are hung off the sound's own timeline from the moment it starts.
    final audioStart = mainStrokeAt + audioOffset;

    // Find the thunder inside the recording. A storm field recording can run
    // for minutes with the real strike somewhere in the middle, so following
    // the file from its start would flash the strip at silence.
    final seek = envelope.strikeStart(windowMs: maxFollowMs);
    final windowEnd = seek + Duration(milliseconds: maxFollowMs);

    // Peak offsets are rebased onto the seek, because playback starts there
    // too: both the light and the sound begin at the same moment in the storm.
    final peaks = envelope
        .peaks(minGapMs: max(minStepGapMs, writeCostMs))
        .where((peak) => peak.at >= seek && peak.at <= windowEnd)
        .map((peak) => EnvelopePeak(
              at: peak.at - seek,
              strength: peak.strength,
              amplitude: peak.amplitude,
              brightness: peak.brightness,
            ))
        .toList();

    final rumble = envelope.rumbleTrack();
    final rumbleOffset = seek.inMilliseconds ~/ envelope.frameMs;

    var previous = cursor;

    for (final peak in peaks) {
      final at = audioStart + peak.at;
      if (at <= previous) continue;

      // Between flashes the strip drops to the rumble, not to black. The low
      // band is what is still sounding in the gaps, so using it as a floor
      // keeps the cloud alive through a long roll instead of leaving it dark
      // between cracks.
      final gapBefore = at - previous;
      if (gapBefore.inMilliseconds > writeCostMs * 2) {
        final midpoint = previous + gapBefore ~/ 2;
        final rumbleIndex = rumbleOffset +
            (midpoint - audioStart).inMilliseconds ~/ envelope.frameMs;

        final floor = rumbleIndex >= 0 && rumbleIndex < rumble.length
            ? rumble[rumbleIndex]
            : 0.0;

        steps.add(FlickerStep(
          at: at - Duration(milliseconds: writeCostMs),
          label: 'rumble ${(floor * 100).round()}%',
          brightness: (255 * floor * energy * 0.22).round().clamp(0, 255),
        ));
      }

      // A sharp crack flashes hard; a dull thump in the same recording gets a
      // softer one. That difference is the whole point of banding the audio,
      // so it is carried straight into the brightness.
      final level = (0.35 + 0.65 * peak.brightness) *
          max(peak.amplitude, peak.strength);

      steps.add(FlickerStep(
        at: at,
        label: 'peak ${(peak.brightness * 100).round()}% sharp',
        brightness: (255 * level * energy).round().clamp(1, 255),
      ));

      previous = at;
    }

    final tail = previous + Duration(milliseconds: 120);
    steps.add(DarkStep(at: tail, label: 'end'));

    return StrikePlan(
      steps: steps,
      mainStrokeAt: mainStrokeAt,
      thunderDelay: Duration(milliseconds: sound.distance.distanceDelayMs),
      sample: sound.distance,
      presetName: '${preset.name} (from sound)',
      audioSeek: seek,
    );
  }

  StrikePlan build(
    ThunderPreset preset,
    StripCalibration calibration, {
    List<BoltSegment> bolts = const [],
  }) {
    final sound = preset.sound;
    final placement = preset.placement;

    final target = resolvePlacement(
      placement,
      calibration,
      bolts: bolts,
    );
    final position = target.position;
    final width = target.width;

    final sharpness = sound.sharpness.clamp(0.0, 1.0);
    final energy = sound.energy.clamp(0.0, 1.0);
    final (red, green, blue) = sound.strikeColor;

    final steps = <StrikeStep>[];
    var cursor = Duration.zero;

    // Mirrors the shadow state the connection keeps, so each step is costed by
    // what it actually changes rather than by its worst case.
    int? heldEffect;
    int? heldSpeed;
    int? heldLength;
    int? heldBrightness;
    int? heldR;
    int? heldG;
    int? heldB;

    /// Appends a step and advances the cursor.
    ///
    /// The gap is whatever the plan asked to hold the light for, or the time
    /// this step's own writes need to go out, whichever is longer. A step can
    /// never be scheduled faster than the link can serve it.
    void hold(StrikeStep step, int holdMs) {
      steps.add(step);
      final floor = max(minStepGapMs, step.writeCost * writeCostMs);
      cursor += Duration(milliseconds: max(holdMs, floor));
    }

    void addSweep({
      required String label,
      required int effect,
      required int speed,
      required int length,
      required int brightness,
      int holdMs = 0,
    }) {
      var cost = 0;
      if (heldEffect != effect) cost++;
      if (heldSpeed != speed) cost++;
      if (heldLength != length) cost++;
      if (heldBrightness != brightness) cost++;
      if (cost == 0) cost = 1;

      hold(
        SweepStep(
          at: cursor,
          label: label,
          writeCost: cost,
          effect: effect,
          speed: speed,
          length: length,
          brightness: brightness,
        ),
        holdMs,
      );

      heldEffect = effect;
      heldSpeed = speed;
      heldLength = length;
      heldBrightness = brightness;
      // A dynamic effect paints its own colours, so whatever RGB the
      // controller held is no longer what is on the strip.
      heldR = null;
      heldG = null;
      heldB = null;
    }

    void addFlood({
      required String label,
      required int brightness,
      int holdMs = 0,
    }) {
      var cost = 0;
      if (heldEffect != Sp621eEffects.solid) cost++;
      if (heldR != red || heldG != green || heldB != blue ||
          heldBrightness != brightness) {
        cost++;
      }
      if (cost == 0) cost = 1;

      hold(
        FloodStep(
          at: cursor,
          label: label,
          writeCost: cost,
          r: red,
          g: green,
          b: blue,
          brightness: brightness,
        ),
        holdMs,
      );

      heldEffect = Sp621eEffects.solid;
      heldR = red;
      heldG = green;
      heldB = blue;
      heldBrightness = brightness;
    }

    /// A brightness-only pulse. Valid only once a colour is already on the
    /// strip, which is why the flicker burst always follows a flood.
    void addFlicker({
      required String label,
      required int brightness,
      int holdMs = 0,
    }) {
      hold(
        FlickerStep(at: cursor, label: label, brightness: brightness),
        holdMs,
      );
      heldBrightness = brightness;
    }

    void addDark({required String label, int holdMs = 0}) {
      hold(DarkStep(at: cursor, label: label), holdMs);
      heldBrightness = 0;
    }

    // -----------------------------------------------------------------
    // Leader
    //
    // A rolling, less sharp strike builds: a dim sweep runs ahead of the
    // main stroke. A hard crack arrives without warning, so high sharpness
    // usually skips this.
    // -----------------------------------------------------------------
    final leaderChance = 0.85 - sharpness * 0.6;
    if (_random.nextDouble() < leaderChance) {
      addSweep(
        label: 'leader',
        effect: placement.sweepEffect,
        speed: placement.speed,
        length: (width * 0.6).round().clamp(1, 150),
        brightness: (255 * energy * 0.28).round().clamp(1, 255),
        holdMs: 90 + _random.nextInt(70),
      );
      addDark(label: 'leader gap', holdMs: 40 + _random.nextInt(40));
    }

    // -----------------------------------------------------------------
    // Main sweep, which is where placement happens
    //
    // The dwell is the whole point: it is how long the block travels before
    // the lights go out, and so where on the strip the bolt appears to land.
    // -----------------------------------------------------------------
    final dwell = calibration.dwellForPosition(
      position,
      placement.speed,
    );

    addSweep(
      label: 'bolt to ${(position * 100).round()}%',
      effect: placement.sweepEffect,
      speed: placement.speed,
      length: width,
      brightness: (255 * energy).round().clamp(1, 255),
      holdMs: dwell.inMilliseconds,
    );

    // -----------------------------------------------------------------
    // Main return stroke. The thunder is timed from this moment.
    // -----------------------------------------------------------------
    final mainStrokeAt = cursor;

    if (placement.floodOnImpact) {
      addFlood(
        label: 'return stroke',
        brightness: (255 * energy).round().clamp(1, 255),
        // A sharp strike flashes briefly and hard; a soft one lingers.
        holdMs: (30 + (1 - sharpness) * 60).round(),
      );

      // -----------------------------------------------------------------
      // Flicker burst
      //
      // The colour is now on the strip, so the return strokes that follow can
      // be brightness alone. That is one write each, which is what lets them
      // sit close enough together to read as a single flickering discharge
      // rather than a series of separate flashes.
      // -----------------------------------------------------------------
      final pulses = 2 + (sharpness * 4).round();
      var pulseEnergy = energy;

      for (var i = 0; i < pulses; i++) {
        addFlicker(
          label: 'flicker ${i + 1} off',
          brightness: 0,
          holdMs: 22 + _random.nextInt(26),
        );

        pulseEnergy *= 0.72 + _random.nextDouble() * 0.22;
        addFlicker(
          label: 'flicker ${i + 1}',
          brightness: (255 * pulseEnergy).round().clamp(1, 255),
          holdMs: 18 + _random.nextInt(30),
        );
      }
    }

    addDark(
      label: 'after stroke',
      holdMs: (40 + (1 - sharpness) * 50).round(),
    );

    // -----------------------------------------------------------------
    // Spatial restrike
    //
    // One more travelling bolt, so a strike is not only a flashing room. Kept
    // to a single sweep because each one costs the link real time.
    // -----------------------------------------------------------------
    if (_random.nextDouble() < 0.35 + sharpness * 0.4) {
      addSweep(
        label: 'restrike bolt',
        effect: placement.sweepEffect,
        speed: placement.speed,
        length: (width * 0.7).round().clamp(1, 150),
        brightness: (255 * energy * 0.7).round().clamp(1, 255),
        holdMs: (dwell.inMilliseconds * 0.5).round(),
      );
      addDark(label: 'restrike gap', holdMs: 35 + _random.nextInt(45));
    }

    // -----------------------------------------------------------------
    // Rumble tail
    //
    // A dim glow held while the sound is still rolling. This is the part that
    // ties the light to a long sample instead of ending abruptly.
    // -----------------------------------------------------------------
    if (sound.rumbleTailMs > 0) {
      addFlood(
        label: 'rumble tail',
        brightness: (255 * energy * 0.12).round().clamp(1, 255),
        holdMs: sound.rumbleTailMs,
      );
    }

    steps.add(DarkStep(at: cursor, label: 'end'));

    return StrikePlan(
      steps: steps,
      mainStrokeAt: mainStrokeAt,
      thunderDelay: Duration(milliseconds: sound.distance.distanceDelayMs),
      sample: sound.distance,
      presetName: preset.name,
    );
  }

  /// A plan that does nothing but park a sweep mid-strip, used by the
  /// calibration screen to time a full traverse.
  static StrikePlan calibrationSweep({
    required int speed,
    required int length,
    int effect = Sp621eEffects.whiteSegmentSpin,
  }) {
    return StrikePlan(
      steps: [
        SweepStep(
          at: Duration.zero,
          label: 'calibration sweep',
          writeCost: 4,
          effect: effect,
          speed: speed,
          length: length,
          brightness: 255,
        ),
      ],
      mainStrokeAt: Duration.zero,
      thunderDelay: Duration.zero,
      presetName: 'Calibration',
    );
  }
}
