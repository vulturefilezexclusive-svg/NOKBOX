import 'dart:convert';
import 'dart:math' as math;

enum EqFilterType { peak, lowShelf, highShelf }

class EqBand {
  const EqBand({required this.freq, this.gainDb = 0, this.q = 1.41, this.type = EqFilterType.peak, this.enabled = true});
  final double freq;
  final double gainDb;
  final double q;
  final EqFilterType type;
  final bool enabled;

  EqBand copyWith({double? freq, double? gainDb, double? q, EqFilterType? type, bool? enabled}) => EqBand(
        freq: freq ?? this.freq,
        gainDb: gainDb ?? this.gainDb,
        q: q ?? this.q,
        type: type ?? this.type,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {'f': freq, 'g': gainDb, 'q': q, 't': type.name, 'on': enabled};
  factory EqBand.fromJson(Map<String, dynamic> j) => EqBand(
        freq: (j['f'] as num).toDouble(),
        gainDb: (j['g'] as num?)?.toDouble() ?? 0,
        q: (j['q'] as num?)?.toDouble() ?? 1.41,
        type: EqFilterType.values.firstWhere((t) => t.name == j['t'], orElse: () => EqFilterType.peak),
        enabled: j['on'] as bool? ?? true,
      );
}

/// A complete equalizer profile: preamp + bands + bass boost + FX.
/// All FX default to off, so a profile with FX untouched sounds exactly
/// like the same profile before FX existed.
class EqProfile {
  const EqProfile({
    required this.name,
    required this.bands,
    this.preampDb = 0,
    this.bassBoostDb = 0,
    this.builtIn = false,
    this.source,
    this.reverbAmount = 0,
    this.reverbRoom = 0.5,
    this.reverbDamping = 0.5,
    this.reverbWet = 0.5,
    this.stereoWidth = 1,
    this.virtualizer = 0,
    this.threeD = 0,
  });

  final String name;
  final List<EqBand> bands;
  final double preampDb;
  final double bassBoostDb;
  final bool builtIn;

  /// Attribution, e.g. "AutoEQ — oratory1990 measurement".
  final String? source;

  /// Reverb (aecho): [reverbAmount] 0..1, 0 = off. [reverbRoom] 0..1 room
  /// size (echo delay spread), [reverbDamping] 0..1 (tail decay),
  /// [reverbWet] 0..1 (echo level).
  final double reverbAmount;
  final double reverbRoom;
  final double reverbDamping;
  final double reverbWet;

  /// Stereo width 0..2 (1 = unchanged, >1 wider, <1 narrower).
  final double stereoWidth;

  /// Headphone virtualizer 0..1, 0 = off (bs2b crossfeed).
  final double virtualizer;

  /// 3D stereo movement 0..1, 0 = off (apulsator LFO sweep).
  final double threeD;

  /// True when any FX is on (i.e. the profile changes the sound beyond EQ).
  bool get fxActive => reverbAmount > 0 || stereoWidth != 1 || virtualizer > 0 || threeD > 0;

  static const graphicFreqs = <double>[31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  static EqProfile graphic(String name, List<double> gains, {double preamp = 0, double bass = 0}) => EqProfile(
        name: name,
        builtIn: true,
        preampDb: preamp,
        bassBoostDb: bass,
        bands: [for (var i = 0; i < graphicFreqs.length; i++) EqBand(freq: graphicFreqs[i], gainDb: gains[i])],
      );

  static final flat = graphic('Flat', List.filled(10, 0));

  static final builtIns = <EqProfile>[
    flat,
    graphic('NOKBOX Knock', [6, 5.5, 3.5, 0.5, -1.5, -0.5, 1, 2, 2.5, 2], preamp: -6),
    graphic('Trap 808', [7, 6, 3, -0.5, -2, -1, 0.5, 1.5, 3, 3.5], preamp: -7),
    graphic('Boom Bap', [4, 4.5, 3, 1, -0.5, 0, 1.5, 2, 1, 0], preamp: -4.5),
    graphic('Drill', [5, 6, 2.5, -1, -1.5, 0.5, 2, 3, 2, 1], preamp: -6),
    graphic('R&B Smooth', [3, 3, 2, 1, 0, -0.5, 0.5, 1.5, 2.5, 2], preamp: -3.5),
    graphic('Vocal Clarity', [-2, -1.5, -0.5, 0.5, 2, 3.5, 3.5, 2.5, 1, 0], preamp: -3.5),
    graphic('Car Slap', [8, 7, 4, 0, -2, -1, 1, 2.5, 3.5, 3], preamp: -8),
    graphic('Headphone Punch', [4, 3.5, 2, 0, -1, 0, 1, 2.5, 3, 2], preamp: -4.5),
    graphic('Treble Boost', [0, 0, 0, 0, 0, 0.5, 1.5, 3, 4.5, 5], preamp: -5),
    graphic('Late Night', [3, 2.5, 1, 0, -1, -1, 0, 1.5, 2.5, 3], preamp: -3),
    graphic('Podcast / Talk', [-4, -3, -1, 1, 2.5, 3, 2.5, 1, -1, -2], preamp: -3),
  ];

  EqProfile copyWith({String? name, List<EqBand>? bands, double? preampDb, double? bassBoostDb, bool? builtIn, String? source, double? reverbAmount, double? reverbRoom, double? reverbDamping, double? reverbWet, double? stereoWidth, double? virtualizer, double? threeD}) => EqProfile(
        name: name ?? this.name,
        bands: bands ?? this.bands,
        preampDb: preampDb ?? this.preampDb,
        bassBoostDb: bassBoostDb ?? this.bassBoostDb,
        builtIn: builtIn ?? this.builtIn,
        source: source ?? this.source,
        reverbAmount: reverbAmount ?? this.reverbAmount,
        reverbRoom: reverbRoom ?? this.reverbRoom,
        reverbDamping: reverbDamping ?? this.reverbDamping,
        reverbWet: reverbWet ?? this.reverbWet,
        stereoWidth: stereoWidth ?? this.stereoWidth,
        virtualizer: virtualizer ?? this.virtualizer,
        threeD: threeD ?? this.threeD,
      );

  /// Rough peak headroom estimate (dB): max of summed positive gains near
  /// band centres. Used to recommend a preamp that avoids clipping.
  double estimatedPeakGain() {
    var maxG = 0.0;
    for (var i = 0; i < 128; i++) {
      final f = 20 * math.pow(1000, i / 127).toDouble();
      final g = responseAt(f) - preampDb;
      if (g > maxG) maxG = g;
    }
    return maxG;
  }

  /// Approximate magnitude response (dB) at [f] — used for the curve view.
  double responseAt(double f) {
    var sum = preampDb;
    for (final b in [...bands, if (bassBoostDb != 0) EqBand(freq: 60, gainDb: bassBoostDb, q: 0.7)]) {
      if (!b.enabled || b.gainDb == 0) continue;
      final x = math.log(f / b.freq) / math.ln2; // octaves away
      switch (b.type) {
        case EqFilterType.peak:
          final bw = 1 / b.q; // ~bandwidth in octaves for moderate Q
          sum += b.gainDb * math.exp(-(x * x) / (2 * math.pow(bw / 1.6, 2)));
        case EqFilterType.lowShelf:
          sum += b.gainDb / (1 + math.exp(4 * x));
        case EqFilterType.highShelf:
          sum += b.gainDb / (1 + math.exp(-4 * x));
      }
    }
    return sum;
  }

  Map<String, dynamic> toJson() => {
        'format': 'nokbox-eq',
        'version': 1,
        'name': name,
        'preamp': preampDb,
        'bass': bassBoostDb,
        'reverbAmount': reverbAmount,
        'reverbRoom': reverbRoom,
        'reverbDamping': reverbDamping,
        'reverbWet': reverbWet,
        'stereoWidth': stereoWidth,
        'virtualizer': virtualizer,
        'threeD': threeD,
        if (source != null) 'source': source,
        'bands': [for (final b in bands) b.toJson()],
      };

  factory EqProfile.fromJson(Map<String, dynamic> j) => EqProfile(
        name: j['name'] as String? ?? 'Custom',
        preampDb: (j['preamp'] as num?)?.toDouble() ?? 0,
        bassBoostDb: (j['bass'] as num?)?.toDouble() ?? 0,
        reverbAmount: (j['reverbAmount'] as num?)?.toDouble() ?? 0,
        reverbRoom: (j['reverbRoom'] as num?)?.toDouble() ?? 0.5,
        reverbDamping: (j['reverbDamping'] as num?)?.toDouble() ?? 0.5,
        reverbWet: (j['reverbWet'] as num?)?.toDouble() ?? 0.5,
        stereoWidth: (j['stereoWidth'] as num?)?.toDouble() ?? 1,
        virtualizer: (j['virtualizer'] as num?)?.toDouble() ?? 0,
        threeD: (j['threeD'] as num?)?.toDouble() ?? 0,
        source: j['source'] as String?,
        bands: [for (final b in (j['bands'] as List? ?? const [])) EqBand.fromJson(Map<String, dynamic>.from(b as Map))],
      );

  String encode() => jsonEncode(toJson());
}
