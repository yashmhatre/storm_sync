import 'package:flutter/material.dart';

/// A scale drawing of the strip, with the lit block where the placement puts
/// it.
///
/// This is a prediction, not a readout: the controller never reports where its
/// sweep has reached, so what is drawn here is only as accurate as the strip
/// calibration behind it.
class StripPreview extends StatelessWidget {
  const StripPreview({
    super.key,
    required this.position,
    required this.widthPixels,
    required this.pixelCount,
    this.brightness = 1.0,
    this.unreachableBelow = 0,
    this.height = 34,
  });

  /// Where the centre of the block lands, 0.0 to 1.0.
  final double position;

  /// Size of the lit block in LEDs.
  final int widthPixels;

  /// Length of the whole strip in LEDs.
  final int pixelCount;

  final double brightness;

  /// Positions nearer than this cannot be hit, because a sweep cannot be cut
  /// short faster than its own commands go out. Drawn as a dead zone.
  final double unreachableBelow;

  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth;
        if (full < 8) return SizedBox(height: height);

        final blockWidth =
            (widthPixels / pixelCount * full).clamp(3.0, full);

        // The sweep starts at the strip's origin and travels right, so the
        // block's trailing edge is what sits at `position`.
        final left =
            (position * full - blockWidth).clamp(0.0, full - blockWidth);

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              if (unreachableBelow > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: (unreachableBelow * full).clamp(0.0, full),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: 0.14),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(6),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: left,
                top: 4,
                bottom: 4,
                width: blockWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.15 * brightness),
                        Colors.white.withValues(alpha: 0.95 * brightness),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.35 * brightness),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Draws a plan's steps along a time axis, so the shape of a strike can be
/// read before it is fired.
class StrikeTimeline extends StatelessWidget {
  const StrikeTimeline({
    super.key,
    required this.marks,
    required this.total,
    this.audioAt,
    this.height = 44,
  });

  /// Each mark is an offset, a 0-1 intensity, and whether it is a sweep.
  final List<({Duration at, double intensity, bool sweep, String label})> marks;
  final Duration total;
  final Duration? audioAt;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final span = total.inMilliseconds;
    if (span <= 0) return SizedBox(height: height);

    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth;
        // During the first layout pass the width can be zero, which would make
        // every clamp below invert its own bounds.
        if (full < 8) return SizedBox(height: height);

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 1,
                child: ColoredBox(color: scheme.outlineVariant),
              ),
              for (final mark in marks)
                Positioned(
                  left: (mark.at.inMilliseconds / span * full)
                      .clamp(0.0, full - 3),
                  bottom: 0,
                  width: 3,
                  height: (height * mark.intensity).clamp(3.0, height),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: mark.sweep ? scheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              if (audioAt != null)
                Positioned(
                  left: (audioAt!.inMilliseconds / span * full)
                      .clamp(0.0, full - 2),
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: ColoredBox(
                    color: scheme.tertiary.withValues(alpha: 0.9),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
