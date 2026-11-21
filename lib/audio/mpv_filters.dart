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
///
/// FX (reverb / stereo width / virtualizer / 3D) are appended to the same
/// `@nokeq` lavfi graph, after the EQ bands. Every FX defaults to off, so
/// a profile with FX untouched produces a chain identical to EQ-only.
class MpvEqBuilder {
  const MpvEqBuilder({this.nativeShelves = false});
  final bool nativeShelves;

  /// [equalizerOnly] builds the same curve without the FX stage. The iOS /
  /// macOS libmpv that media_kit ships is compiled with a trimmed libavfilter
  /// (`--disable-all --enable-filter=overlay --enable-filter=equalizer`), so
  /// aeco/extrastereo/bs2b/apulsator do not exist there and a chain that
  /// mentions one is rejected — taking every sound with it. Playback retries
  /// with this chain so the EQ can never silence the player.
  String build(EqProfile p, {bool enabled = true, bool equalizerOnly = false}) {
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
    if (!equalizerOnly) _appendFx(parts, p);
    if (parts.isEmpty) return '';
    // Labelled lavfi graph so we can replace it atomically.
    return '@nokeq:lavfi=[${parts.join(',')}]';
  }

  /// Appends the FX filters. Each FX is emitted only when it is on, so the
  /// chain for an FX-free profile is byte-identical to the old EQ-only one.
  void _appendFx(List<String> parts, EqProfile p) {
    // Reverb: aecho=in_gain:out_gain:delays:decays. Room size stretches the
    // echo delays (50..200 ms base tap); damping shortens the later taps'
    // decay; wet scales the echo level. Amount scales the overall decay.
    if (p.reverbAmount > 0) {
      final amt = p.reverbAmount.clamp(0.0, 1.0);
      final room = p.reverbRoom.clamp(0.0, 1.0);
      final damp = p.reverbDamping.clamp(0.0, 1.0);
      final wet = p.reverbWet.clamp(0.0, 1.0);
      final d1 = (50 + 150 * room).round(); // 50..200 ms
      final base = (0.25 + 0.45 * amt) * wet;
      final dec1 = base.clamp(0.05, 0.9);
      final dec2 = (base * (1 - 0.4 * damp)).clamp(0.05, 0.9);
      final dec3 = (base * (1 - 0.7 * damp)).clamp(0.05, 0.9);
      parts.add('aecho=0.8:0.9:$d1|${d1 * 2}|${d1 * 3}:${_n(dec1)}|${_n(dec2)}|${_n(dec3)}');
    }
    // Stereo width: extrastereo m in [-1, 1]; width 1 -> m 0 (no change).
    if (p.stereoWidth != 1) {
      final m = ((p.stereoWidth.clamp(0.0, 2.0) - 1) * 0.5).clamp(-1.0, 1.0);
      parts.add('extrastereo=m=${_n(m)}');
    }
    // Virtualizer: bs2b crossfeed for headphones. Profile steps up with the
    // amount (default -> cmoy -> jmeier). NOTE: bs2b needs FFmpeg built with
    // --enable-libbs2b; if the device build lacks it, mpv rejects the chain
    // only while virtualizer is on — verify on device.
    if (p.virtualizer > 0) {
      final v = p.virtualizer.clamp(0.0, 1.0);
      final profile = v < 0.34 ? 'default' : v < 0.67 ? 'cmoy' : 'jmeier';
      parts.add('bs2b=profile=$profile');
    }
    // 3D: slow LFO stereo sweep (apulsator). offset_r defaults to 0.5, so
    // the L/R channels move out of phase — an autopanner-like 3D drift.
    if (p.threeD > 0) {
      parts.add('apulsator=mode=sine:amount=${_n(p.threeD.clamp(0.0, 1.0))}:hz=0.25');
    }
  }

  /// mpv's software volume is cubic: gain = (vol/100)^3. Converts a dB
  /// preamp into a volume multiplier.
  static double preampToVolumeFactor(double db) => math.pow(10, db / 60).toDouble();

  static String _n(double v) {
    final s = v.toStringAsFixed(2);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }
}
