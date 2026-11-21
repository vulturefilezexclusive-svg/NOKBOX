import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

/// SQLite storage (FTS5 search index, playlists, history, lyrics cache,
/// resume points, queues, downloads). Synchronous FFI calls are fast enough
/// for UI use; bulk indexing writes run in a single transaction.
class NokDatabase {
  NokDatabase(this.db) {
    _migrate();
  }

  factory NokDatabase.open(String path) => NokDatabase(sqlite3.open(path));
  factory NokDatabase.memory() => NokDatabase(sqlite3.openInMemory());

  final Database db;
  bool _fts = true;

  void _migrate() {
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('''
      CREATE TABLE IF NOT EXISTS tracks (
        id TEXT PRIMARY KEY,
        json TEXT NOT NULL,
        mtime INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        art TEXT,
        created INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS playlist_items (
        playlist_id INTEGER NOT NULL,
        pos INTEGER NOT NULL,
        track_id TEXT NOT NULL,
        track_json TEXT
      );
      CREATE TABLE IF NOT EXISTS history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_id TEXT NOT NULL,
        track_json TEXT NOT NULL,
        played_at INTEGER NOT NULL,
        listened_ms INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS history_track ON history(track_id);
      CREATE INDEX IF NOT EXISTS history_time ON history(played_at);
      CREATE TABLE IF NOT EXISTS lyrics_cache (
        key TEXT PRIMARY KEY,
        synced TEXT,
        plain TEXT,
        source TEXT,
        fetched INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS resume (
        key TEXT PRIMARY KEY,
        position_ms INTEGER NOT NULL,
        updated INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS kv (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS favorites (
        track_id TEXT PRIMARY KEY,
        track_json TEXT NOT NULL,
        added INTEGER NOT NULL
      );
    ''');
    try {
      db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS tracks_fts USING fts5(id UNINDEXED, title, artist, album, genre, filename, lyrics, tokenize='unicode61 remove_diacritics 2');");
    } catch (_) {
      _fts = false;
    }
  }

  bool get hasFts => _fts;

  // ---------------- tracks ----------------
  void upsertTracks(Iterable<Track> tracks) {
    final st = db.prepare('INSERT OR REPLACE INTO tracks(id, json, mtime) VALUES (?, ?, ?)');
    final del = _fts ? db.prepare('DELETE FROM tracks_fts WHERE id = ?') : null;
    final fts = _fts ? db.prepare('INSERT INTO tracks_fts(id, title, artist, album, genre, filename, lyrics) VALUES (?,?,?,?,?,?,?)') : null;
    db.execute('BEGIN');
    try {
      for (final t in tracks) {
        st.execute([t.id, t.encode(), t.dateAdded]);
        del?.execute([t.id]);
        fts?.execute([t.id, t.title, t.artist, t.album, t.genre, t.uri.split('/').last, t.lyrics ?? '']);
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      st.close();
      del?.close();
      fts?.close();
    }
  }

  void deleteTracks(Iterable<String> ids) {
    db.execute('BEGIN');
    try {
      for (final id in ids) {
        db.execute('DELETE FROM tracks WHERE id = ?', [id]);
        if (_fts) db.execute('DELETE FROM tracks_fts WHERE id = ?', [id]);
      }
      db.execute('COMMIT');
    } catch (e) {
      // Never leave the connection inside an open transaction: every later
      // write would fail with "cannot start a transaction within a
      // transaction" for the rest of the session.
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Track> allTracks() => [
        for (final r in db.select('SELECT json FROM tracks'))
          Track.decode(r['json'] as String),
      ];

  Map<String, int> trackMtimes() => {
        for (final r in db.select('SELECT id, mtime FROM tracks')) r['id'] as String: r['mtime'] as int,
      };

  /// FTS5 prefix search; returns matching track ids ordered by rank.
  List<String> searchIds(String query, {int limit = 300}) {
    if (!_fts) return const [];
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((t) => t.isNotEmpty)
        .map((t) => '"$t"*')
        .join(' ');
    if (tokens.isEmpty) return const [];
    try {
      return [
        for (final r in db.select('SELECT id FROM tracks_fts WHERE tracks_fts MATCH ? ORDER BY rank LIMIT ?', [tokens, limit]))
          r['id'] as String,
      ];
    } catch (_) {
      return const [];
    }
  }

  // ---------------- playlists ----------------
  List<Playlist> playlists() {
    final rows = db.select('SELECT * FROM playlists ORDER BY created DESC');
    return [
      for (final r in rows)
        Playlist(
          id: r['id'] as int,
          name: r['name'] as String,
          description: r['description'] as String,
          artUri: r['art'] as String?,
          createdAt: r['created'] as int,
          trackIds: [
            for (final i in db.select('SELECT track_id FROM playlist_items WHERE playlist_id = ? ORDER BY pos', [r['id']]))
              i['track_id'] as String,
          ],
        ),
    ];
  }

  int createPlaylist(String name, {String description = ''}) {
    db.execute('INSERT INTO playlists(name, description, created) VALUES (?, ?, ?)', [name, description, DateTime.now().millisecondsSinceEpoch]);
    return db.lastInsertRowId;
  }

  void renamePlaylist(int id, String name) => db.execute('UPDATE playlists SET name = ? WHERE id = ?', [name, id]);

  void deletePlaylist(int id) {
    db.execute('DELETE FROM playlist_items WHERE playlist_id = ?', [id]);
    db.execute('DELETE FROM playlists WHERE id = ?', [id]);
  }

  void addToPlaylist(int id, List<Track> tracks) {
    final r = db.select('SELECT COALESCE(MAX(pos), -1) AS m FROM playlist_items WHERE playlist_id = ?', [id]);
    var pos = (r.first['m'] as int) + 1;
    for (final t in tracks) {
      db.execute('INSERT INTO playlist_items(playlist_id, pos, track_id, track_json) VALUES (?,?,?,?)', [id, pos++, t.id, t.isLocal ? null : t.encode()]);
    }
  }

  void setPlaylistOrder(int id, List<String> trackIds) {
    final json = {for (final r in db.select('SELECT track_id, track_json FROM playlist_items WHERE playlist_id = ?', [id])) r['track_id'] as String: r['track_json'] as String?};
    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM playlist_items WHERE playlist_id = ?', [id]);
      var pos = 0;
      for (final t in trackIds) {
        db.execute('INSERT INTO playlist_items(playlist_id, pos, track_id, track_json) VALUES (?,?,?,?)', [id, pos++, t, json[t]]);
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Remote tracks stored inline in playlists.
  Map<String, Track> playlistRemoteTracks() => {
        for (final r in db.select('SELECT track_id, track_json FROM playlist_items WHERE track_json IS NOT NULL'))
          r['track_id'] as String: Track.decode(r['track_json'] as String),
      };

  // ---------------- favourites ----------------
  Set<String> favoriteIds() => {for (final r in db.select('SELECT track_id FROM favorites')) r['track_id'] as String};
  List<Track> favoriteTracks() => [for (final r in db.select('SELECT track_json FROM favorites ORDER BY added DESC')) Track.decode(r['track_json'] as String)];
  void setFavorite(Track t, bool fav) {
    if (fav) {
      db.execute('INSERT OR REPLACE INTO favorites(track_id, track_json, added) VALUES (?,?,?)', [t.id, t.encode(), DateTime.now().millisecondsSinceEpoch]);
    } else {
      db.execute('DELETE FROM favorites WHERE track_id = ?', [t.id]);
    }
  }

  // ---------------- history / stats ----------------
  void logPlay(Track t, int listenedMs) {
    db.execute('INSERT INTO history(track_id, track_json, played_at, listened_ms) VALUES (?,?,?,?)', [t.id, t.encode(), DateTime.now().millisecondsSinceEpoch, listenedMs]);
  }

  List<(Track, int)> recentHistory({int limit = 100}) => [
        for (final r in db.select('SELECT track_json, played_at FROM history ORDER BY played_at DESC LIMIT ?', [limit]))
          (Track.decode(r['track_json'] as String), r['played_at'] as int),
      ];

  List<(Track, int, int)> mostPlayed({int? sinceMs, int limit = 50}) => [
        for (final r in db.select(
          'SELECT track_json, COUNT(*) AS c, SUM(listened_ms) AS ms FROM history WHERE played_at >= ? GROUP BY track_id ORDER BY c DESC, ms DESC LIMIT ?',
          [sinceMs ?? 0, limit],
        ))
          (Track.decode(r['track_json'] as String), r['c'] as int, (r['ms'] as int?) ?? 0),
      ];

  List<(String, int, int)> topArtists({int? sinceMs, int limit = 20}) {
    final map = <String, (int, int)>{};
    for (final r in db.select('SELECT track_json, listened_ms FROM history WHERE played_at >= ?', [sinceMs ?? 0])) {
      final t = Track.decode(r['track_json'] as String);
      final a = t.displayArtist;
      final cur = map[a] ?? (0, 0);
      map[a] = (cur.$1 + 1, cur.$2 + (r['listened_ms'] as int));
    }
    final list = [for (final e in map.entries) (e.key, e.value.$1, e.value.$2)]..sort((a, b) => b.$2.compareTo(a.$2));
    return list.take(limit).toList();
  }

  /// Total listened ms per day (local), last [days] days.
  Map<DateTime, int> listeningByDay({int days = 30}) {
    final since = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final out = <DateTime, int>{};
    for (final r in db.select('SELECT played_at, listened_ms FROM history WHERE played_at >= ?', [since])) {
      final d = DateTime.fromMillisecondsSinceEpoch(r['played_at'] as int);
      final k = DateTime(d.year, d.month, d.day);
      out[k] = (out[k] ?? 0) + (r['listened_ms'] as int);
    }
    return out;
  }

  int totalListenedMs() => (db.select('SELECT COALESCE(SUM(listened_ms),0) AS s FROM history').first['s'] as int);
  int playCount(String trackId) => db.select('SELECT COUNT(*) AS c FROM history WHERE track_id = ?', [trackId]).first['c'] as int;

  /// Play counts for every track in one query, for sorting by "most played".
  Map<String, int> playCounts() => {
        for (final r in db.select('SELECT track_id, COUNT(*) AS c FROM history GROUP BY track_id'))
          r['track_id'] as String: r['c'] as int,
      };

  void clearHistory() => db.execute('DELETE FROM history');

  List<Map<String, Object?>> exportHistory() => [
        for (final r in db.select('SELECT track_json, played_at, listened_ms FROM history ORDER BY played_at'))
          {'track': jsonDecode(r['track_json'] as String), 'playedAt': r['played_at'], 'listenedMs': r['listened_ms']},
      ];

  /// Merge-import: skips entries already present (same track & timestamp).
  int importHistory(List<dynamic> entries) {
    var n = 0;
    db.execute('BEGIN');
    try {
      for (final e in entries) {
        final m = e as Map;
        final t = Track.fromJson(Map<String, dynamic>.from(m['track'] as Map));
        final at = (m['playedAt'] as num).toInt();
        final exists = db.select('SELECT 1 FROM history WHERE track_id = ? AND played_at = ?', [t.id, at]).isNotEmpty;
        if (exists) continue;
        db.execute('INSERT INTO history(track_id, track_json, played_at, listened_ms) VALUES (?,?,?,?)', [t.id, t.encode(), at, (m['listenedMs'] as num?)?.toInt() ?? 0]);
        n++;
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return n;
  }

  // ---------------- lyrics cache ----------------
  ({String? synced, String? plain, String? source})? cachedLyrics(String key) {
    final r = db.select('SELECT synced, plain, source FROM lyrics_cache WHERE key = ?', [key]);
    if (r.isEmpty) return null;
    return (synced: r.first['synced'] as String?, plain: r.first['plain'] as String?, source: r.first['source'] as String?);
  }

  void cacheLyrics(String key, {String? synced, String? plain, String source = 'lrclib'}) {
    db.execute('INSERT OR REPLACE INTO lyrics_cache(key, synced, plain, source, fetched) VALUES (?,?,?,?,?)', [key, synced, plain, source, DateTime.now().millisecondsSinceEpoch]);
  }

  int lyricsCacheCount() => db.select('SELECT COUNT(*) AS c FROM lyrics_cache').first['c'] as int;
  void clearLyricsCache() => db.execute('DELETE FROM lyrics_cache');

  // ---------------- resume points ----------------
  void saveResume(String key, int positionMs) =>
      db.execute('INSERT OR REPLACE INTO resume(key, position_ms, updated) VALUES (?,?,?)', [key, positionMs, DateTime.now().millisecondsSinceEpoch]);
  int? resumeFor(String key) {
    final r = db.select('SELECT position_ms FROM resume WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['position_ms'] as int;
  }

  void clearResume(String key) => db.execute('DELETE FROM resume WHERE key = ?', [key]);

  // ---------------- key/value (queues, downloads, eq) ----------------
  String? kvGet(String key) {
    final r = db.select('SELECT value FROM kv WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String;
  }

  void kvSet(String key, String value) => db.execute('INSERT OR REPLACE INTO kv(key, value) VALUES (?, ?)', [key, value]);

  void close() => db.close();
}
