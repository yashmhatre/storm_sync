import 'dart:math';
import 'dart:typed_data';

/// A small radix-2 Cooley-Tukey FFT.
///
/// Written out rather than pulled in as a dependency because this is the only
/// signal processing the app needs, and the band analysis it feeds is the whole
/// reason the flicker can follow the sound rather than just its loudness.
class Fft {
  Fft(this.size)
      : assert(size > 0 && (size & (size - 1)) == 0,
            'FFT size must be a power of two'),
        _cos = Float64List(size ~/ 2),
        _sin = Float64List(size ~/ 2) {
    // Twiddle factors are the same for every frame, so they are worked out
    // once and reused across the whole recording.
    for (var i = 0; i < size ~/ 2; i++) {
      final angle = -2 * pi * i / size;
      _cos[i] = cos(angle);
      _sin[i] = sin(angle);
    }
  }

  final int size;
  final Float64List _cos;
  final Float64List _sin;

  /// Transforms [real] and [imaginary] in place.
  void transform(Float64List real, Float64List imaginary) {
    assert(real.length == size && imaginary.length == size);

    // Bit-reversal permutation.
    var j = 0;
    for (var i = 0; i < size - 1; i++) {
      if (i < j) {
        var temp = real[i];
        real[i] = real[j];
        real[j] = temp;
        temp = imaginary[i];
        imaginary[i] = imaginary[j];
        imaginary[j] = temp;
      }
      var k = size >> 1;
      while (k <= j) {
        j -= k;
        k >>= 1;
      }
      j += k;
    }

    // Butterflies.
    for (var span = 1; span < size; span <<= 1) {
      final step = size ~/ (span << 1);
      for (var group = 0; group < span; group++) {
        final twiddle = group * step;
        final wr = _cos[twiddle];
        final wi = _sin[twiddle];

        for (var pair = group; pair < size; pair += span << 1) {
          final match = pair + span;
          final tr = wr * real[match] - wi * imaginary[match];
          final ti = wr * imaginary[match] + wi * real[match];

          real[match] = real[pair] - tr;
          imaginary[match] = imaginary[pair] - ti;
          real[pair] += tr;
          imaginary[pair] += ti;
        }
      }
    }
  }

  /// Magnitude of each bin up to Nyquist.
  Float64List magnitudes(Float64List samples) {
    final real = Float64List(size);
    final imaginary = Float64List(size);

    final count = min(samples.length, size);
    for (var i = 0; i < count; i++) {
      // A Hann window stops the edges of each frame ringing across the whole
      // spectrum, which would smear a sharp crack into the low bands.
      final window = 0.5 - 0.5 * cos(2 * pi * i / (size - 1));
      real[i] = samples[i] * window;
    }

    transform(real, imaginary);

    final half = size ~/ 2;
    final output = Float64List(half);
    for (var i = 0; i < half; i++) {
      output[i] = sqrt(real[i] * real[i] + imaginary[i] * imaginary[i]);
    }
    return output;
  }

  /// The frequency, in Hz, that bin [index] represents.
  double frequencyOf(int index, int sampleRate) => index * sampleRate / size;

  /// The bin nearest to [frequency].
  int binFor(double frequency, int sampleRate) =>
      (frequency * size / sampleRate).round().clamp(0, size ~/ 2 - 1);
}
