import 'package:flutter/material.dart';

import '../../model/params.dart';
import '../theme.dart';

/// A labelled slider bound to one firmware parameter.
///
/// While a drag is in progress the widget renders its own local value, so the
/// thumb tracks the finger at full frame rate even though only ten writes a
/// second actually reach the device. The moment the finger lifts it hands
/// control back to [value], which reflects what the device last reported.
class ParamSlider extends StatefulWidget {
  const ParamSlider({
    super.key,
    required this.spec,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ParamSpec spec;

  /// Current value, or null if the device has not reported this key yet.
  final int? value;

  final bool enabled;

  /// Called continuously during a drag with `isFinal: false`, then once on
  /// release with `isFinal: true`.
  final void Function(int value, {required bool isFinal}) onChanged;

  @override
  State<ParamSlider> createState() => _ParamSliderState();
}

class _ParamSliderState extends State<ParamSlider> {
  int? _dragValue;

  int get _effective =>
      _dragValue ?? widget.value ?? widget.spec.min;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = widget.spec;
    final unknown = widget.value == null && _dragValue == null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(spec.label, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(width: 8),
              Text(
                unknown ? '--' : '$_effective',
                style: kMonoStyle.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: unknown
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _Bound(text: '${spec.min}'),
              Expanded(
                child: Slider(
                  min: spec.min.toDouble(),
                  max: spec.max.toDouble(),
                  divisions: spec.divisions,
                  value: _effective
                      .clamp(spec.min, spec.max)
                      .toDouble(),
                  label: '$_effective',
                  onChanged: widget.enabled
                      ? (raw) {
                          final snapped = spec.snap(raw);
                          if (snapped == _dragValue) return;
                          setState(() => _dragValue = snapped);
                          widget.onChanged(snapped, isFinal: false);
                        }
                      : null,
                  onChangeEnd: widget.enabled
                      ? (raw) {
                          final snapped = spec.snap(raw);
                          // Always deliver the value the finger stopped on,
                          // even if the throttle just dropped an identical one.
                          widget.onChanged(snapped, isFinal: true);
                          setState(() => _dragValue = null);
                        }
                      : null,
                ),
              ),
              _Bound(text: '${spec.max}'),
            ],
          ),
          if (spec.description != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                spec.description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bound extends StatelessWidget {
  const _Bound({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: kMonoStyle.copyWith(
        fontSize: 10,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
