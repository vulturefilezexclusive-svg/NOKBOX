import '../data/models.dart';
import '../library/text_utils.dart';
import 'source_provider.dart';

/// Auto source switching: when a stream fails, find the same recording
/// elsewhere. Order: local library → download-permitted sources → other
/// legit streams. Match: ISRC → MusicBrainz ID → fuzzy (title/artist
/// similarity + duration within ±3 s, rejecting version mismatches).
class SourceMatcher {
  SourceMatcher({required this.localTracks, required this.providers});

  final List<Track> Function() localTracks;
  final List<SourceProvider> Function() providers;

  static const _versionWords = ['live', 'remix', 'sped up', 'slowed', 'instrumental', 'nightcore', 'karaoke', 'cover', 'acapella', 'reverb', '8d'];

  static double score(Track want, Track cand) {
    if (want.isrc != null && want.isrc!.isNotEmpty && want.isrc == cand.isrc) return 1.0;
    if (want.mbid != null && want.mbid!.isNotEmpty && want.mbid == cand.mbid) return 1.0;
    if (want.durationMs > 0 && cand.durationMs > 0 && (want.durationMs - cand.durationMs).abs() > 3000) return 0;
    final wt = want.title.toLowerCase(), ct = cand.title.toLowerCase();
    for (final w in _versionWords) {
      final rw = RegExp('\\b${RegExp.escape(w)}\\b');
      if (rw.hasMatch(wt) != rw.hasMatch(ct)) return 0;
    }
    final ts = similarity(normalizeTitle(want.title), normalizeTitle(cand.title));
    final as = similarity(normalizeArtist(want.artist), normalizeArtist(cand.artist));
    return ts * 0.6 + as * 0.4;
  }

  Future<Track?> findAlternative(Track failed, {double threshold = 0.82, Set<String> exclude = const {}}) async {
    Track? best;
    var bestScore = 0.0;
    void consider(Track c) {
      if (c.id == failed.id || exclude.contains(c.id) || c.extra['collection'] == true) return;
      final s = score(failed, c);
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }

    for (final t in localTracks()) {
      consider(t);
    }
    if (bestScore >= threshold) return best;

    final ps = providers().where((p) => p.id != failed.source && p.setupHint == null).toList();
    // Download-permitted catalogs first.
    const preferred = [SourceIds.youtube, SourceIds.archive];
    ps.sort((a, b) => (preferred.contains(a.id) ? 0 : 1).compareTo(preferred.contains(b.id) ? 0 : 1));
    final q = '${failed.artist} ${normalizeTitle(failed.title)}'.trim();
    for (final p in ps) {
      if (p.id == SourceIds.radio || p.id == SourceIds.podcast) continue;
      try {
        for (final c in await p.search(q)) {
          consider(c);
        }
      } catch (_) {}
      if (bestScore >= threshold) return best;
    }
    return bestScore >= threshold ? best : null;
  }
}
