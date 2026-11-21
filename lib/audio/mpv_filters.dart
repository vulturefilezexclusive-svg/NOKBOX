import 'dart:math' as math;

import 'eq.dart';

/// Translates an [EqProfile] into an mpv `af` filter chain using FFmpeg's
/// `equalizer` (peaking biquad) filter, which is compiled into media_kit's
/// iOS/macOS libmpv builds. Because those builds do not ship `lowshelf` /
/// `highshelf`, shelves are approximated with a cascade of wide peaking
/// filters unless [nativeShelves] is true (desktop/full FFmpeg builds).
///
/// Works identically for local files and network streams because mpv runs
/// the filter graph on decoded PCM regardless of the source.
class MpvEqBuilder {
  const MpvEqBuilder({this.nativeShelves = false});
  final bool nativeShelves;

  String build(EqProfile p, {bool enabled = true}) {
    if (!enabled) return '';
    final parts = <String>[];
    void peak(double f, double q, double g) {
      if (g.abs() < 0.05) return;
      final ff = f.clamp(16.0, 22000.0);
      parts.add('equalizer=f=${_n(ff)}:t=q:w=${_n(q.clamp(0.1, 20))}:g=${_n(g.clamp(-24, 24))}');
    }

    for (final b in p.bands) {
      if (!b.enabled) continue;
      switch (b.type) {
        case EqFilterType.peak:
          peak(b.freq, b.q, b.gainDb);
        case EqFilterType.lowShelf:
          if (nativeShelves) {
            parts.add('lowshelf=f=${_n(b.freq)}:t=q:w=${_n(b.q)}:g=${_n(b.gainDb)}');
          } else {
            // Shelf ≈ broad peaks at f/2 and f/4 (each half gain), keeps the
            // plateau below the corner frequency.
            peak(b.freq / 2, 0.6, b.gainDb * 0.6);
            peak(math.max(b.freq / 4, 20), 0.6, b.gainDb * 0.5);
          }
        case EqFilterType.highShelf:
          if (nativeShelves) {
            parts.add('highshelf=f=${_n(b.freq)}:t=q:w=${_n(b.q)}:g=${_n(b.gainDb)}');
          } else {
            peak(b.freq * 2, 0.6, b.gainDb * 0.6);
            peak(math.min(b.freq * 4, 20000), 0.6, b.gainDb * 0.5);
          }
      }
    }
    if (p.bassBoostDb > 0) {
      peak(55, 0.8, p.bassBoostDb);
      peak(110, 1.2, p.bassBoostDb * 0.35);
    }
    if (parts.isEmpty) return '';
    // Labelled lavfi graph so we can replace it atomically.
    return '@nokeq:lavfi=[${parts.join(',')}]';
  }

  /// mpv's software volume is cubic: gain = (vol/100)^3. Converts a dB
  /// preamp into a volume multiplier.
  static double preampToVolumeFactor(double db) => math.pow(10, db / 60).toDouble();

  static String _n(double v) {
    final s = v.toStringAsFixed(2);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }
}
