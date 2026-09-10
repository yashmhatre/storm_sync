import 'package:flutter/material.dart';

/// A dark, low-glare theme. The app gets used in a dim room next to a light
/// that is meant to be the brightest thing there.
ThemeData buildStormTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6C8CFF),
    brightness: Brightness.dark,
  ).copyWith(
    surface: const Color(0xFF11141B),
    surfaceContainerLowest: const Color(0xFF0B0D12),
    surfaceContainer: const Color(0xFF171B24),
    surfaceContainerHigh: const Color(0xFF1E232E),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0B0D12),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 6,
      // Sliders here are dragged with a thumb, often one-handed, so give the
      // grab target some size.
      thumbSize: WidgetStatePropertyAll(Size(10, 26)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

/// Monospace stack for the log and for numeric readouts, so digits do not
/// shuffle sideways as values change.
const List<String> kMonoFallback = [
  'Roboto Mono',
  'DroidSansMono',
  'Menlo',
  'Consolas',
  'monospace',
];

const TextStyle kMonoStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: kMonoFallback,
);
