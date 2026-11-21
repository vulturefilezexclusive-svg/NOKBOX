import 'dart:convert';

import '../audio/equalizer_controller.dart';
import '../core/settings.dart';
import '../core/theme/theme_controller.dart';
import '../data/database.dart';
import '../data/models.dart';

/// Backup/restore in a documented, mergeable JSON format:
///
/// ```json
/// {
///   "format": "nokbox-backup", "version": 1, "createdAt": "<ISO-8601>",
///   "settings": { ...SettingsStore json... },
///   "theme": { ...NokThemeSpec json... },
///   "savedThemes": [ ... ],
///   "equalizer": { "enabled", "profile", "custom", "outputs" },
///   "playlists": [ { "name", "description", "tracks": [Track json] } ],
///   "favorites": [Track json],
///   "history": [ { "track": Track json, "playedAt": epochMs, "listenedMs" } ],
///   "queues": "<QueueSet json string>"
/// }
/// ```
/// Restoring merges: playlists with the same name get missing tracks
/// appended, history entries are de-duplicated by (track, timestamp).
class BackupService {
  BackupService({required this.db, required this.settings, required this.theme, required this.eq});
  final NokDatabase db;
  final SettingsStore settings;
  final ThemeController theme;
  final EqualizerController eq;

  String export() {
    final remote = db.playlistRemoteTracks();
    final all = {for (final t in db.allTracks()) t.id: t};
    return const JsonEncoder.withIndent(' ').convert({
      'format': 'nokbox-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'settings': settings.toJson(),
      'theme': theme.spec.toJson(),
      'savedThemes': [for (final s in theme.saved) s.toJson()],
      'equalizer': eq.exportJson(),
      'playlists': [
        for (final p in db.playlists())
          {
            'name': p.name,
            'description': p.description,
            'tracks': [for (final id in p.trackIds) if ((all[id] ?? remote[id]) != null) (all[id] ?? remote[id])!.toJson()],
          },
      ],
      'favorites': [for (final t in db.favoriteTracks()) t.toJson()],
      'history': db.exportHistory(),
      'queues': db.kvGet('queues'),
    });
  }

  /// Returns a human summary.
  Future<String> restore(String json) async {
    final j = jsonDecode(json) as Map<String, dynamic>;
    if (j['format'] != 'nokbox-backup') throw const FormatException('Not a NOKBOX backup');
    if (j['settings'] is Map) await settings.importJson(Map<String, dynamic>.from(j['settings'] as Map));
    for (final s in (j['savedThemes'] as List? ?? const [])) {
      await theme.importTheme(jsonEncode(s));
    }
    if (j['theme'] is Map) await theme.importTheme(jsonEncode(j['theme']));
    if (j['equalizer'] is Map) {
      db.kvSet('eq.state', jsonEncode(j['equalizer']));
    }
    var plCount = 0;
    final existing = {for (final p in db.playlists()) p.name: p};
    for (final p in (j['playlists'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(p as Map);
      final tracks = [for (final t in (m['tracks'] as List? ?? const [])) Track.fromJson(Map<String, dynamic>.from(t as Map))];
      final ex = existing[m['name']];
      if (ex == null) {
        final id = db.createPlaylist(m['name'] as String, description: m['description'] as String? ?? '');
        db.addToPlaylist(id, tracks);
      } else {
        db.addToPlaylist(ex.id, tracks.where((t) => !ex.trackIds.contains(t.id)).toList());
      }
      plCount++;
    }
    for (final f in (j['favorites'] as List? ?? const [])) {
      db.setFavorite(Track.fromJson(Map<String, dynamic>.from(f as Map)), true);
    }
    final h = db.importHistory(j['history'] as List? ?? const []);
    if (j['queues'] is String && db.kvGet('queues') == null) db.kvSet('queues', j['queues'] as String);
    return 'Restored $plCount playlists, $h history entries, settings, themes & EQ.';
  }
}
