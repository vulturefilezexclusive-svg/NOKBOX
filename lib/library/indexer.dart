import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path/path.dart' as p;

import '../data/models.dart';

const audioExtensions = {
  '.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.oga', '.alac', '.aiff', '.aif', '.wma', '.mka', '.ape', '.wv', '.dsf',
};
const videoExtensions = {'.mp4', '.m4v', '.mov', '.mkv', '.webm', '.avi', '.3gp'};
const coverNames = ['cover', 'folder', 'front', 'album', 'artwork', 'albumart'];

class IndexOptions {
  IndexOptions({
    required this.roots,
    required this.excluded,
    required this.artDir,
    this.minDurationSec = 30,
    this.minSizeKb = 100,
    this.includeVideos = true,
    this.known = const {},
    this.forceRetag = false,
  });
  final List<String> roots;
  final List<String> excluded;
  final String artDir;
  final int minDurationSec;
  final int minSizeKb;
  final bool includeVideos;

  /// id -> mtime of tracks already indexed (incremental re-index).
  final Map<String, int> known;

  /// Read tags again even when the mtime is unchanged (used when the duration
  /// floor changed, which mtimes cannot reveal). [known] is still passed so
  /// files deleted from disk are still reported in
  /// [IndexResult.removedIds] — the old code dropped the map entirely and so
  /// lost that detection for the scan.
  final bool forceRetag;
}

class IndexResult {
  IndexResult(this.added, this.removedIds, this.unchanged, this.skipped);
  final List<Track> added;
  final List<String> removedIds;
  final int unchanged;
  final int skipped;
}

/// Runs the scan in a background isolate so the UI never janks.
Future<IndexResult> runIndexer(IndexOptions o) {
  final args = {
    'roots': o.roots,
    'excluded': o.excluded,
    'artDir': o.artDir,
    'minDur': o.minDurationSec,
    'minKb': o.minSizeKb,
    'videos': o.includeVideos,
    'known': o.known,
    'retag': o.forceRetag,
  };
  return Isolate.run(() {
    final r = _scan(args);
    return IndexResult(
      [for (final j in r['added'] as List) Track.fromJson(Map<String, dynamic>.from(j as Map))],
      List<String>.from(r['removed'] as List),
      r['unchanged'] as int,
      r['skipped'] as int,
    );
  });
}

Map<String, Object> _scan(Map<String, Object> a) {
  final roots = List<String>.from(a['roots'] as List);
  final excluded = List<String>.from(a['excluded'] as List).map((e) => p.normalize(e)).toList();
  final artDir = a['artDir'] as String;
  final minDur = a['minDur'] as int;
  final minKb = a['minKb'] as int;
  final videos = a['videos'] as bool;
  final known = Map<String, int>.from(a['known'] as Map);
  final retag = a['retag'] as bool? ?? false;
  Directory(artDir).createSync(recursive: true);

  final seen = <String>{};
  final dropped = <String>{};
  final added = <Map<String, dynamic>>[];
  var unchanged = 0, skipped = 0;
  final folderCover = <String, String?>{};

  bool isExcluded(String path) => excluded.any((e) => p.isWithin(e, path) || p.equals(e, path));

  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    final Iterable<FileSystemEntity> entries;
    try {
      entries = dir.listSync(recursive: true, followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in entries) {
      if (e is! File) continue;
      final path = e.path;
      if (p.basename(path).startsWith('.')) continue;
      if (isExcluded(path)) continue;
      final ext = p.extension(path).toLowerCase();
      final isVideo = videoExtensions.contains(ext);
      if (!audioExtensions.contains(ext) && !(videos && isVideo)) continue;
      final id = 'local:$path';
      seen.add(id);
      final FileStat st;
      try {
        st = e.statSync();
      } catch (_) {
        continue;
      }
      final mtime = st.modified.millisecondsSinceEpoch;
      // The size is already known from the stat, so check it before the
      // incremental shortcut: raising "minimum file size" must drop tracks
      // indexed under a lower limit instead of keeping them forever.
      if (st.size < minKb * 1024) {
        dropped.add(id);
        skipped++;
        continue;
      }
      if (!retag && known[id] == mtime) {
        unchanged++;
        continue;
      }
      final folder = p.dirname(path);
      String title = p.basenameWithoutExtension(path);
      String artist = '', album = '', albumArtist = '', genre = '';
      int? year, trackNo, discNo, bitrate, sampleRate;
      int durationMs = 0;
      String? lyrics, artPath;
      if (!isVideo) {
        try {
          final m = readMetadata(e, getImage: true);
          title = (m.title?.trim().isNotEmpty ?? false) ? m.title!.trim() : title;
          artist = m.artist?.trim() ?? '';
          album = m.album?.trim() ?? '';
          albumArtist = m.albumArtist?.trim() ?? '';
          genre = m.genres.join(', ');
          year = m.year?.year;
          trackNo = m.trackNumber;
          discNo = m.discNumber;
          durationMs = m.duration?.inMilliseconds ?? 0;
          bitrate = m.bitrate;
          sampleRate = m.sampleRate;
          lyrics = m.lyrics;
          if (m.pictures.isNotEmpty) {
            final pic = m.pictures.first;
            final key = _hash('${album.toLowerCase()}|${(albumArtist.isNotEmpty ? albumArtist : artist).toLowerCase()}|${album.isEmpty ? path : folder}');
            final out = File(p.join(artDir, '$key${pic.mimetype.contains('png') ? '.png' : '.jpg'}'));
            if (!out.existsSync()) out.writeAsBytesSync(pic.bytes);
            artPath = out.path;
          }
        } catch (_) {
          // Unreadable tags: fall back to filename parsing below.
        }
      }
      if (artist.isEmpty && title.contains(' - ')) {
        final parts = title.split(' - ');
        artist = parts.first.trim();
        title = parts.sublist(1).join(' - ').trim();
      }
      if (!isVideo && durationMs > 0 && durationMs < minDur * 1000) {
        dropped.add(id);
        skipped++;
        continue;
      }
      // Artwork fallback chain: embedded -> folder image.
      artPath ??= folderCover.putIfAbsent(folder, () => _findFolderCover(folder));
      // Sidecar .lrc
      final lrc = File(p.setExtension(path, '.lrc'));
      if (lyrics == null && lrc.existsSync()) {
        try {
          lyrics = lrc.readAsStringSync();
        } catch (_) {}
      }
      added.add(Track(
        id: id,
        uri: path,
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        genre: genre,
        year: year,
        trackNo: trackNo,
        discNo: discNo,
        durationMs: durationMs,
        sizeBytes: st.size,
        bitrate: bitrate,
        sampleRate: sampleRate,
        format: ext.replaceFirst('.', '').toUpperCase(),
        artUri: artPath,
        folder: folder,
        dateAdded: mtime,
        isVideo: isVideo,
        lyrics: lyrics,
        download: DownloadCapability.allowed,
      ).toJson());
    }
  }
  // Files that vanished from disk, plus files still on disk that no longer
  // pass the filters. Filtered ids used to stay in the library forever.
  final removed = <String>{...known.keys.where((k) => !seen.contains(k)), ...dropped}.toList();
  return {'added': added, 'removed': removed, 'unchanged': unchanged, 'skipped': skipped};
}

String? _findFolderCover(String folder) {
  try {
    for (final f in Directory(folder).listSync()) {
      if (f is! File) continue;
      final name = p.basenameWithoutExtension(f.path).toLowerCase();
      final ext = p.extension(f.path).toLowerCase();
      if ((ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp') && coverNames.contains(name)) return f.path;
    }
  } catch (_) {}
  return null;
}

String _hash(String s) {
  // FNV-1a 64-bit (non-cryptographic), stable file names for art cache.
  var h = 0xcbf29ce484222325;
  for (final c in utf8.encode(s)) {
    h ^= c;
    h = h * 0x100000001b3;
  }
  return h.toUnsigned(64).toRadixString(16);
}

/// Removes duplicates (same normalized title+artist and duration within 1.5s),
/// keeping the highest quality file.
List<Track> dedupe(List<Track> tracks) {
  final best = <String, Track>{};
  final out = <Track>[];
  for (final t in tracks) {
    final k = '${t.title.toLowerCase().trim()}|${t.artist.toLowerCase().trim()}|${(t.durationMs / 1500).round()}';
    final cur = best[k];
    if (cur == null) {
      best[k] = t;
    } else if ((t.bitrate ?? 0) * 1000 + t.sizeBytes ~/ 1000 > (cur.bitrate ?? 0) * 1000 + cur.sizeBytes ~/ 1000) {
      best[k] = t;
    }
  }
  final keep = best.values.map((t) => t.id).toSet();
  for (final t in tracks) {
    if (keep.contains(t.id)) out.add(t);
  }
  return out;
}
