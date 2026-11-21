import 'dart:math' as math;

/// Splits an artist string on user-configured separators and extracts
/// "feat."/"ft."/"with" credits from both artist and title fields.
class ArtistParser {
  ArtistParser({required this.separators, this.extractFeat = true});
  final List<String> separators;
  final bool extractFeat;

  static final _featRe = RegExp(r'[\(\[]?\s*\b(?:feat\.?|ft\.?|featuring)\s+([^\)\]]+)[\)\]]?', caseSensitive: false);

  List<String> split(String artist, {String title = ''}) {
    final out = <String>[];
    void addAll(String s) {
      var parts = <String>[s];
      for (final sep in separators) {
        if (sep.isEmpty) continue;
        parts = [
          for (final p in parts)
            ...(sep.trim().isEmpty || sep.trim().length > 1 || sep.startsWith(' ')
                ? p.split(RegExp(RegExp.escape(sep), caseSensitive: false))
                : p.split(sep))
        ];
      }
      for (final p in parts) {
        final t = p.trim();
        if (t.isNotEmpty && !out.any((o) => o.toLowerCase() == t.toLowerCase())) out.add(t);
      }
    }

    var main = artist;
    if (extractFeat) {
      final m = _featRe.firstMatch(main);
      if (m != null) {
        main = main.substring(0, m.start);
        addAll(main);
        addAll(m.group(1)!);
      } else {
        addAll(main);
      }
      final tm = _featRe.firstMatch(title);
      if (tm != null) addAll(tm.group(1)!);
    } else {
      addAll(main);
    }
    return out;
  }
}

List<String> splitGenres(String genre, List<String> separators) {
  var parts = <String>[genre];
  for (final sep in separators) {
    parts = [for (final p in parts) ...p.split(sep)];
  }
  return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
}

/// Normalizes a title for cross-source matching: lowercases, removes
/// feat. credits, bracketed qualifiers like (Official Video)/(Remastered),
/// punctuation and extra whitespace.
String normalizeTitle(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll(RegExp(r'[\(\[][^\)\]]*(official|video|audio|lyric|visualizer|remaster|explicit|clean|hd|hq|4k)[^\)\]]*[\)\]]'), ' ');
  t = t.replaceAll(RegExp(r'\b(feat\.?|ft\.?|featuring)\b.*$'), ' ');
  t = t.replaceAll(RegExp(r"[^\p{L}\p{N}\s]", unicode: true), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String normalizeArtist(String s) {
  var t = s.toLowerCase();
  t = t.replaceAll(RegExp(r'\b(feat\.?|ft\.?|featuring|x|&|and|with)\b'), ' ');
  t = t.replaceAll(RegExp(r'\s*-\s*topic$'), '');
  t = t.replaceAll(RegExp(r"[^\p{L}\p{N}\s]", unicode: true), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}

/// 0..1 similarity combining edit distance and token overlap.
double similarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  final lev = 1 - levenshtein(a, b) / math.max(a.length, b.length);
  final ta = a.split(' ').toSet(), tb = b.split(' ').toSet();
  final jac = ta.intersection(tb).length / ta.union(tb).length;
  return math.max(lev, jac);
}

/// Typo-tolerant contains: true if every query token is found (or nearly
/// found, ≤1 edit for tokens ≥4 chars) among the haystack tokens.
bool fuzzyContains(String haystack, String query) {
  final h = haystack.toLowerCase();
  final tokens = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  final hTokens = h.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)).where((t) => t.isNotEmpty).toList();
  for (final t in tokens) {
    if (h.contains(t)) continue;
    if (t.length < 4) return false;
    final ok = hTokens.any((ht) => (ht.length - t.length).abs() <= 1 && levenshtein(ht, t) <= 1 ||
        (ht.length > t.length && levenshtein(ht.substring(0, t.length), t) <= 1));
    if (!ok) return false;
  }
  return true;
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}
