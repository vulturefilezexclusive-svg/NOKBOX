import 'eq.dart';

/// Parses AutoEQ exports (https://github.com/jaakkopasanen/AutoEq, MIT).
///
/// Supported formats:
///  * `ParametricEQ.txt`:
///      Preamp: -6.2 dB
///      Filter 1: ON LSC Fc 105 Hz Gain 5.5 dB Q 0.70
///      Filter 2: ON PK Fc 2200 Hz Gain -3.1 dB Q 1.41
///  * `GraphicEQ.txt` (Wavelet / EqualizerAPO GraphicEQ):
///      GraphicEQ: 20 -2.1; 21 -2.0; ...
///
/// Measurements are produced by third parties (oratory1990, crinacle,
/// Rtings, Innerfidelity, ...). Always keep the attribution in [EqProfile.source].
class AutoEqParser {
  static final _filter = RegExp(
    r'Filter\s*\d*\s*:\s*(ON|OFF)\s+(PK|PEQ|LSC|LS|HSC|HS|LSQ|HSQ)\s+Fc\s+([\d.]+)\s*Hz\s+Gain\s+(-?[\d.]+)\s*dB(?:\s+Q\s+([\d.]+))?',
    caseSensitive: false,
  );
  static final _preamp = RegExp(r'Preamp\s*:\s*(-?[\d.]+)\s*dB', caseSensitive: false);

  static EqProfile parse(String text, {String name = 'AutoEQ import', String? attribution}) {
    if (text.contains('GraphicEQ:')) return _graphic(text, name, attribution);
    final pre = _preamp.firstMatch(text);
    final bands = <EqBand>[];
    for (final m in _filter.allMatches(text)) {
      final type = switch (m.group(2)!.toUpperCase()) {
        'LSC' || 'LS' || 'LSQ' => EqFilterType.lowShelf,
        'HSC' || 'HS' || 'HSQ' => EqFilterType.highShelf,
        _ => EqFilterType.peak,
      };
      bands.add(EqBand(
        freq: double.parse(m.group(3)!),
        gainDb: double.parse(m.group(4)!),
        q: double.tryParse(m.group(5) ?? '') ?? 0.707,
        type: type,
        enabled: m.group(1)!.toUpperCase() == 'ON',
      ));
    }
    if (bands.isEmpty) throw const FormatException('No AutoEQ filters found');
    return EqProfile(
      name: name,
      bands: bands,
      preampDb: pre == null ? 0 : double.parse(pre.group(1)!),
      source: attribution ?? 'AutoEQ (MIT) — measurement credits apply',
    );
  }

  /// Reduces a dense GraphicEQ curve to the 10 graphic bands by sampling.
  static EqProfile _graphic(String text, String name, String? attribution) {
    final body = text.split('GraphicEQ:').last;
    final pts = <(double, double)>[];
    for (final part in body.split(';')) {
      final xs = part.trim().split(RegExp(r'\s+'));
      if (xs.length < 2) continue;
      final f = double.tryParse(xs[0]), g = double.tryParse(xs[1]);
      if (f != null && g != null) pts.add((f, g));
    }
    if (pts.isEmpty) throw const FormatException('Empty GraphicEQ');
    double at(double f) {
      (double, double)? best;
      for (final p in pts) {
        if (best == null || (p.$1 - f).abs() < (best.$1 - f).abs()) best = p;
      }
      return best!.$2;
    }

    final gains = [for (final f in EqProfile.graphicFreqs) at(f)];
    final maxG = gains.fold<double>(0, (a, b) => b > a ? b : a);
    return EqProfile(
      name: name,
      preampDb: -maxG,
      bands: [for (var i = 0; i < gains.length; i++) EqBand(freq: EqProfile.graphicFreqs[i], gainDb: gains[i])],
      source: attribution ?? 'AutoEQ (MIT) — measurement credits apply',
    );
  }
}
