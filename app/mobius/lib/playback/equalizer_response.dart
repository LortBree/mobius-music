import 'dart:math' as math;

/// Dart mirror of the engine's 10-band graphic equalizer
/// (`rust/audio-core/src/equalizer.rs`): same centre frequencies, the same
/// RBJ peaking biquads (Q = 1.4), the same filter-gain solve and the same
/// auto-preamp rule. The UI uses it to draw the real combined response and
/// to show the preamp the engine applies, so what is drawn is what is heard.
///
/// The bands overlap, so the engine does not set each filter to the user's
/// gain directly: it SOLVES the filter gains so the combined curve passes
/// through every set value at the band centres (the dots sit on the line).
abstract final class EqualizerResponse {
  static const List<double> bandsHz = [
    31,
    62,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];
  static const double minGainDb = -12;
  static const double maxGainDb = 12;
  static const double _q = 1.4;
  static const double _maxFilterGainDb = 24;

  /// Display rate. The curve barely changes with rate below 16 kHz.
  static const double referenceRate = 48000;

  /// Combined response in dB at [frequency] for the user's [gainsDb].
  static double responseDb(
    List<double> gainsDb,
    double frequency, {
    double sampleRate = referenceRate,
  }) {
    final filters = filterGainsDb(gainsDb, sampleRate: sampleRate);
    var total = 0.0;
    for (var band = 0; band < bandsHz.length; band++) {
      if (filters[band].abs() < 1e-12) continue; // a 0 dB band is identity
      total += _bandResponseDb(
        _coefficients(bandsHz[band], filters[band], sampleRate),
        frequency,
        sampleRate,
      );
    }
    return total;
  }

  static List<double>? _cacheInput;
  static double _cacheRate = 0;
  static List<double> _cacheOutput = const [];

  /// The per-filter gains the engine actually uses for [gainsDb]. Cached
  /// for the last input, since one paint asks for hundreds of points.
  static List<double> filterGainsDb(
    List<double> gainsDb, {
    double sampleRate = referenceRate,
  }) {
    final cached = _cacheInput;
    if (cached != null && _cacheRate == sampleRate && _same(cached, gainsDb)) {
      return _cacheOutput;
    }
    final solved = _solve(gainsDb, sampleRate);
    _cacheInput = List<double>.of(gainsDb);
    _cacheRate = sampleRate;
    _cacheOutput = solved;
    return solved;
  }

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Quasi-Newton solve, identical to `solve_filter_gains` in Rust: the
  /// interaction matrix (dB at centre i per dB of band j) is built once at
  /// 1 dB and a few correction steps absorb the small non-linearity.
  static List<double> _solve(List<double> targets, double rate) {
    const n = 10;
    if (targets.every((g) => g.abs() < 1e-9)) {
      return List<double>.filled(n, 0);
    }
    final active = [for (final f in bandsHz) f <= rate * 0.45];
    final centres = [for (final f in bandsHz) math.min(f, rate * 0.49)];
    final unit = [
      for (var j = 0; j < n; j++) _coefficients(bandsHz[j], 1, rate),
    ];
    final matrix = [
      for (var i = 0; i < n; i++)
        [
          for (var j = 0; j < n; j++)
            active[i] && active[j]
                ? _bandResponseDb(unit[j], centres[i], rate)
                : (i == j ? 1.0 : 0.0),
        ],
    ];

    final gains = List<double>.of(targets);
    for (var iteration = 0; iteration < 12; iteration++) {
      final filters = [
        for (var j = 0; j < n; j++) _coefficients(bandsHz[j], gains[j], rate),
      ];
      final residual = List<double>.filled(n, 0);
      var worst = 0.0;
      for (var i = 0; i < n; i++) {
        if (!active[i]) continue;
        var actual = 0.0;
        for (final c in filters) {
          actual += _bandResponseDb(c, centres[i], rate);
        }
        residual[i] = targets[i] - actual;
        worst = math.max(worst, residual[i].abs());
      }
      if (worst < 1e-7) break;
      final step = _solveLinear(matrix, residual);
      for (var j = 0; j < n; j++) {
        if (active[j]) {
          gains[j] = (gains[j] + step[j])
              .clamp(-_maxFilterGainDb, _maxFilterGainDb)
              .toDouble();
        }
      }
    }
    return gains;
  }

  /// Gaussian elimination with partial pivoting (copies its inputs).
  static List<double> _solveLinear(List<List<double>> m, List<double> rhs) {
    const n = 10;
    final a = [for (final row in m) List<double>.of(row)];
    final b = List<double>.of(rhs);
    for (var col = 0; col < n; col++) {
      var pivot = col;
      for (var r = col + 1; r < n; r++) {
        if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
      }
      final rowTmp = a[col];
      a[col] = a[pivot];
      a[pivot] = rowTmp;
      final bTmp = b[col];
      b[col] = b[pivot];
      b[pivot] = bTmp;
      final diag = a[col][col];
      if (diag.abs() < 1e-12) continue;
      for (var r = col + 1; r < n; r++) {
        final factor = a[r][col] / diag;
        if (factor == 0) continue;
        for (var k = col; k < n; k++) {
          a[r][k] -= factor * a[col][k];
        }
        b[r] -= factor * b[col];
      }
    }
    final x = List<double>.filled(n, 0);
    for (var r = n - 1; r >= 0; r--) {
      var tail = 0.0;
      for (var k = r + 1; k < n; k++) {
        tail += a[r][k] * x[k];
      }
      final diag = a[r][r];
      x[r] = diag.abs() < 1e-12 ? 0 : (b[r] - tail) / diag;
    }
    return x;
  }

  static double _bandResponseDb(_Biquad k, double frequency, double rate) {
    final omega = 2 * math.pi * frequency / rate;
    final c1 = math.cos(omega), s1 = -math.sin(omega);
    final c2 = math.cos(2 * omega), s2 = -math.sin(2 * omega);
    final numRe = k.b0 + k.b1 * c1 + k.b2 * c2;
    final numIm = k.b1 * s1 + k.b2 * s2;
    final denRe = 1 + k.a1 * c1 + k.a2 * c2;
    final denIm = k.a1 * s1 + k.a2 * s2;
    final num = numRe * numRe + numIm * numIm;
    final den = math.max(denRe * denRe + denIm * denIm, 1e-300);
    return 10 * math.log(num / den) / math.ln10;
  }

  /// Input attenuation (<= 0 dB) the engine applies so boosts never clip.
  static double autoPreampDb(
    List<double> gainsDb, {
    double sampleRate = referenceRate,
  }) {
    const points = 240;
    const low = 20.0;
    final high = math.min(20000.0, sampleRate * 0.49);
    var peak = double.negativeInfinity;
    for (var i = 0; i < points; i++) {
      final f = low * math.pow(high / low, i / (points - 1));
      peak = math.max(
        peak,
        responseDb(gainsDb, f.toDouble(), sampleRate: sampleRate),
      );
    }
    for (final f in bandsHz) {
      if (f <= high) {
        peak = math.max(peak, responseDb(gainsDb, f, sampleRate: sampleRate));
      }
    }
    return -math.max(peak, 0.0);
  }

  static _Biquad _coefficients(double centre, double gainDb, double rate) {
    final frequency = math.min(centre, rate * 0.49);
    final a = math.pow(10, gainDb / 40).toDouble();
    final omega = 2 * math.pi * frequency / rate;
    final cos = math.cos(omega);
    final alpha = math.sin(omega) / (2 * _q);
    final a0 = 1 + alpha / a;
    return _Biquad(
      b0: (1 + alpha * a) / a0,
      b1: (-2 * cos) / a0,
      b2: (1 - alpha * a) / a0,
      a1: (-2 * cos) / a0,
      a2: (1 - alpha / a) / a0,
    );
  }
}

class _Biquad {
  const _Biquad({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  final double b0, b1, b2, a1, a2;
}

/// Built-in curves. Kept moderate: the auto preamp costs loudness equal to
/// the curve's peak, so extreme presets mostly just make everything quieter.
abstract final class EqualizerPresets {
  static const String custom = 'Custom';

  static const Map<String, List<double>> all = {
    'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'Bass boost': [5, 4.5, 3.5, 1.5, 0, 0, 0, 0, 0, 0],
    'Warm': [2, 2.5, 2, 1, 0, -0.5, -1, -1, -0.5, 0],
    'Vocal': [-2, -1.5, -0.5, 1, 2.5, 3, 2.5, 1, 0, -1],
    'Rock': [4, 3, 1.5, -0.5, -1, -0.5, 1, 2.5, 3.5, 3.5],
    'Electronic': [4.5, 4, 1.5, 0, -1.5, 0, 1, 1.5, 3.5, 4],
    'Acoustic': [3, 2.5, 1.5, 0.5, 1, 1, 2, 2.5, 2, 1.5],
    'Treble boost': [0, 0, 0, 0, 0, 0.5, 1.5, 3, 4, 4.5],
  };

  /// The preset matching [gains], or [custom].
  static String nameFor(List<double> gains) {
    for (final entry in all.entries) {
      var same = true;
      for (var i = 0; i < 10; i++) {
        if ((entry.value[i] - gains[i]).abs() >= 0.01) {
          same = false;
          break;
        }
      }
      if (same) return entry.key;
    }
    return custom;
  }
}
