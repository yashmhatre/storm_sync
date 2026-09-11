import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/sound_pack.dart';
import '../../audio/thunder_player.dart';
import 'sound_pack_sheet.dart';

/// Animated waveform visualizer showing live audio activity and active sound pack.
class AudioWaveformVisualizer extends StatefulWidget {
  const AudioWaveformVisualizer({super.key});

  @override
  State<AudioWaveformVisualizer> createState() => _AudioWaveformVisualizerState();
}

class _AudioWaveformVisualizerState extends State<AudioWaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final thunder = context.watch<ThunderPlayer>();
    final packManager = context.watch<SoundPackManager>();
    final isPlaying = thunder.isPlaying;
    final activeDistance = thunder.activePlayingDistance;

    return Card(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          children: [
            // Top Bar: Sound Pack name and change button
            Row(
              children: [
                Icon(
                  Icons.graphic_eq,
                  size: 18,
                  color: isPlaying ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sound Pack: ${packManager.activePack.name}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (isPlaying && activeDistance != null)
                        Text(
                          'Playing: ${activeDistance.label.toUpperCase()} THUNDER',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const SoundPackSheet(),
                  ),
                  icon: const Icon(Icons.library_music_outlined, size: 16),
                  label: const Text('Packs'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Animated Waveform Bars
            SizedBox(
              height: 48,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(double.infinity, 48),
                    painter: _WaveformPainter(
                      progress: _controller.value,
                      isPlaying: isPlaying,
                      distance: activeDistance,
                      primaryColor: scheme.primary,
                      idleColor: scheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.progress,
    required this.isPlaying,
    required this.distance,
    required this.primaryColor,
    required this.idleColor,
  });

  final double progress;
  final bool isPlaying;
  final ThunderDistance? distance;
  final Color primaryColor;
  final Color idleColor;

  static const int barCount = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = (size.width / (barCount * 1.6)).clamp(3.0, 7.0);
    final spacing = (size.width - (barCount * barWidth)) / (barCount - 1);
    final centerY = size.height / 2;

    // Amplitude multiplier based on distance
    final double ampMultiplier;
    switch (distance) {
      case ThunderDistance.close:
        ampMultiplier = 1.0;
      case ThunderDistance.mid:
        ampMultiplier = 0.65;
      case ThunderDistance.far:
      case null:
        ampMultiplier = 0.35;
    }

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    for (var i = 0; i < barCount; i++) {
      final x = i * (barWidth + spacing) + barWidth / 2;
      final normalizedIndex = i / barCount;

      double heightFactor;
      if (isPlaying) {
        final wave1 = math.sin((progress * 2 * math.pi) + (normalizedIndex * 4 * math.pi));
        final wave2 = math.cos((progress * 4 * math.pi) - (normalizedIndex * 2 * math.pi));
        final envelope = math.sin(normalizedIndex * math.pi);
        heightFactor = (0.3 + 0.7 * (wave1.abs() * 0.6 + wave2.abs() * 0.4)) *
            envelope *
            ampMultiplier;
        paint.color = Color.lerp(
          primaryColor.withValues(alpha: 0.7),
          const Color(0xFF90CAF9),
          wave1.abs(),
        )!;
      } else {
        // Idle gentle breathing baseline
        final idleWave = math.sin((progress * 2 * math.pi) + (normalizedIndex * 2 * math.pi));
        heightFactor = 0.12 + 0.08 * idleWave.abs();
        paint.color = idleColor;
      }

      final barHeight = (size.height * heightFactor).clamp(4.0, size.height);
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.distance != distance;
  }
}
