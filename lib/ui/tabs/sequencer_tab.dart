import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../audio/sequence_engine.dart';
import '../../audio/thunder_player.dart';
import '../../ble/storm_service.dart';
import '../../model/app_settings.dart';
import '../../model/storm_sequence.dart';
import '../theme.dart';

/// Interactive Sequencer Tab for automated multi-strike choreographies.
class SequencerTab extends StatefulWidget {
  const SequencerTab({super.key});

  @override
  State<SequencerTab> createState() => _SequencerTabState();
}

class _SequencerTabState extends State<SequencerTab>
    with AutomaticKeepAliveClientMixin {
  late StormSequence _selectedSequence;
  bool _looping = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selectedSequence = StormSequence.builtInSequences.first;
    _looping = _selectedSequence.isLooping;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final service = context.watch<StormService>();
    final engine = context.watch<SequenceEngine>();
    final thunder = context.watch<ThunderPlayer>();
    final settings = context.watch<AppSettings>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = service.isConnected;

    final isThisSequenceRunning =
        engine.isRunning && engine.currentSequence?.id == _selectedSequence.id;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Sequence selector header
        _buildSequenceSelector(scheme),
        const SizedBox(height: 16),

        // Playback Controller Card
        Card(
          color: scheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedSequence.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedSequence.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: _looping,
                      label: const Text('Loop'),
                      avatar: Icon(
                        Icons.repeat,
                        size: 16,
                        color: _looping ? scheme.onPrimary : scheme.onSurfaceVariant,
                      ),
                      onSelected: isThisSequenceRunning
                          ? null
                          : (val) {
                              setState(() {
                                _looping = val;
                                _selectedSequence =
                                    _selectedSequence.copyWith(isLooping: val);
                              });
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: isThisSequenceRunning
                        ? engine.progress
                        : (engine.status == SequenceStatus.completed ? 1.0 : 0.0),
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHigh,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isThisSequenceRunning ? scheme.primary : scheme.outline,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Play / Stop Action
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: isThisSequenceRunning
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: scheme.onError,
                          ),
                          onPressed: () => engine.stop(),
                          icon: const Icon(Icons.stop),
                          label: const Text(
                            'STOP SEQUENCE',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: enabled
                              ? () {
                                  engine.start(
                                    sequence: _selectedSequence.copyWith(
                                      isLooping: _looping,
                                    ),
                                    stormService: service,
                                    thunderPlayer: thunder,
                                    appSettings: settings,
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            enabled ? 'START SEQUENCE' : 'CONNECT LIGHT TO PLAY',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Timeline Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Timeline Steps (${_selectedSequence.steps.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'Total: ${(_selectedSequence.totalDurationMs / 1000).toStringAsFixed(1)}s',
              style: kMonoStyle.copyWith(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Steps list
        ...List.generate(_selectedSequence.steps.length, (index) {
          final step = _selectedSequence.steps[index];
          final isCurrentStep =
              isThisSequenceRunning && engine.currentStepIndex == index;

          return _TimelineStepCard(
            stepNumber: index + 1,
            step: step,
            isActive: isCurrentStep,
          );
        }),
      ],
    );
  }

  Widget _buildSequenceSelector(ColorScheme scheme) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: StormSequence.builtInSequences.map((seq) {
          final isSelected = seq.id == _selectedSequence.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(seq.name),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedSequence = seq;
                    _looping = seq.isLooping;
                  });
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TimelineStepCard extends StatelessWidget {
  const _TimelineStepCard({
    required this.stepNumber,
    required this.step,
    required this.isActive,
  });

  final int stepNumber;
  final SequenceStep step;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isActive
            ? scheme.primaryContainer.withValues(alpha: 0.3)
            : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.25),
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Step Index Indicator
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isActive ? scheme.primary : scheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$stepNumber',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isActive ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Step Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      step.command,
                      style: kMonoStyle.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isActive ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                    if (step.distance != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.volume_up, size: 12, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              step.distance!.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                if (step.label.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    step.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Timing delay badge
          Text(
            '+${step.delayBeforeMs}ms',
            style: kMonoStyle.copyWith(
              fontSize: 12,
              color: isActive ? scheme.primary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

