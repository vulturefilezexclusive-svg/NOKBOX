import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/settings.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../library/text_utils.dart';
import 'lrc.dart';
import 'lrclib_client.dart';

/// Lyrics for the current track: embedded/sidecar first, offline cache,
/// then LRCLIB. Results are cached so lyrics work offline afterwards.
class LyricsController extends ChangeNotifier {
  LyricsController({required this.db, required this.settings, LrclibClient? client}) : _client = client ?? LrclibClient();
  final NokDatabase db;
  final SettingsStore settings;
  final LrclibClient _client;

  Track? _track;
  Lyrics? lyrics;
  bool loading = false;
  String? error;
  Duration userOffset = Duration.zero;

  static String keyFor(Track t) => '${normalizeArtist(t.artist)}|${normalizeTitle(t.title)}|${(t.durationMs / 2000).round()}';

  Future<void> load(Track? t, {bool force = false}) async {
    if (t == null) {
      _track = null;
      lyrics = null;
      notifyListeners();
      return;
    }
    if (!force && _track?.id == t.id) return;
    _track = t;
    lyrics = null;
    error = null;
    userOffset = Duration.zero;
    loading = true;
    notifyListeners();
    try {
      lyrics = await _resolve(t, force: force);
    } catch (e) {
      error = 'Lyrics unavailable';
    }
    if (_track?.id == t.id) {
      loading = false;
      notifyListeners();
    }
  }

  Future<Lyrics?> _resolve(Track t, {bool force = false}) async {
    if (!force && t.lyrics != null && t.lyrics!.trim().isNotEmpty) return parseLrc(t.lyrics!, source: 'Embedded');
    final key = keyFor(t);
    final cached = force ? null : db.cachedLyrics(key);
    if (cached != null) {
      if (cached.synced != null) return parseLrc(cached.synced!, source: cached.source ?? 'Cache');
      if (cached.plain != null) return Lyrics(plain: cached.plain, source: cached.source ?? 'Cache');
      return null;
    }
    if (!settings.lyricsAutoFetch && !force) return null;
    final r = await _client.get(title: normalizeTitle(t.title).isEmpty ? t.title : t.title, artist: t.artist, album: t.album, durationSec: t.durationMs ~/ 1000);
    db.cacheLyrics(key, synced: r?.synced, plain: r?.plain, source: 'LRCLIB');
    if (r?.synced != null && settings.lyricsSaveLrc && t.isLocal) {
      try {
        File(p.setExtension(t.uri, '.lrc')).writeAsStringSync(r!.synced!);
      } catch (_) {}
    }
    if (r == null) return null;
    if (r.synced != null) return parseLrc(r.synced!, source: 'LRCLIB');
    if (r.instrumental) return Lyrics(plain: '♪ Instrumental ♪', source: 'LRCLIB');
    return Lyrics(plain: r.plain, source: 'LRCLIB');
  }

  void nudgeOffset(int ms) {
    userOffset += Duration(milliseconds: ms);
    notifyListeners();
  }

  /// Saves user-edited lyrics to the cache (and .lrc sidecar if enabled).
  void saveEdited(Track t, String text) {
    final l = parseLrc(text, source: 'Edited');
    db.cacheLyrics(keyFor(t), synced: l.synced ? text : null, plain: l.synced ? null : text, source: 'Edited');
    if (t.isLocal && settings.lyricsSaveLrc) {
      try {
        File(p.setExtension(t.uri, '.lrc')).writeAsStringSync(text);
      } catch (_) {}
    }
    lyrics = l;
    notifyListeners();
  }
}
