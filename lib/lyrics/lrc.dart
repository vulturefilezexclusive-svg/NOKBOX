/// One lyric line; [words] is non-empty for word-synced (enhanced LRC).
class LyricLine {
  LyricLine(this.time, this.text, {this.words = const []});
  final Duration time;
  final String text;
  final List<(Duration, String)> words;
}

class Lyrics {
  Lyrics({this.lines = const [], this.plain, this.source = '', this.offset = Duration.zero});
  final List<LyricLine> lines;
  final String? plain;
  final String source;
  final Duration offset;
  bool get synced => lines.isNotEmpty;
  bool get isEmpty => lines.isEmpty && (plain == null || plain!.trim().isEmpty);

  /// Index of the active line at [pos] (binary search).
  int indexAt(Duration pos) {
    final p = pos + offset;
    var lo = 0, hi = lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= p) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }
}

final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _wordTag = RegExp(r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>');
final _offsetTag = RegExp(r'\[offset:\s*([+-]?\d+)\]', caseSensitive: false);

Duration _dur(String m, String s, String? f) {
  var ms = 0;
  if (f != null) {
    ms = f.length == 1 ? int.parse(f) * 100 : f.length == 2 ? int.parse(f) * 10 : int.parse(f);
  }
  return Duration(minutes: int.parse(m), seconds: int.parse(s), milliseconds: ms);
}

/// Parses standard and enhanced (word-synced) LRC. Lines with multiple
/// timestamps are expanded. Returns plain lyrics when no tags are found.
Lyrics parseLrc(String text, {String source = ''}) {
  final lines = <LyricLine>[];
  var offset = Duration.zero;
  final om = _offsetTag.firstMatch(text);
  if (om != null) offset = Duration(milliseconds: int.parse(om.group(1)!));
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final tags = _timeTag.allMatches(raw).toList();
    if (tags.isEmpty) continue;
    final body = raw.substring(tags.last.end);
    final words = <(Duration, String)>[];
    final wm = _wordTag.allMatches(body).toList();
    for (var i = 0; i < wm.length; i++) {
      final end = i + 1 < wm.length ? wm[i + 1].start : body.length;
      words.add((_dur(wm[i].group(1)!, wm[i].group(2)!, wm[i].group(3)), body.substring(wm[i].end, end)));
    }
    final clean = body.replaceAll(_wordTag, '').trim();
    for (final t in tags) {
      lines.add(LyricLine(_dur(t.group(1)!, t.group(2)!, t.group(3)), clean, words: words));
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  if (lines.isEmpty) return Lyrics(plain: text, source: source);
  return Lyrics(lines: lines, source: source, offset: offset, plain: lines.map((l) => l.text).join('\n'));
}

String toLrc(Lyrics l) {
  String ts(Duration d) =>
      '[${d.inMinutes.toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}.${(d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0')}]';
  return l.lines.map((e) => '${ts(e.time)}${e.text}').join('\n');
}
