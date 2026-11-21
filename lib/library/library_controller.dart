import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/settings.dart';
import '../data/database.dart';
import '../data/models.dart';
import 'indexer.dart';
import 'text_utils.dart';

enum TrackSort { title, artist, album, year, dateAdded, duration, size, mostPlayed, filename }

/// Unified library: local files plus favourited/downloaded remote tracks.
class LibraryController extends ChangeNotifier {
  LibraryController({required this.db, required this.settings, required this.documentsDir, required this.artDir}) {
    _viewPrint = _computeViewPrint();
    settings.addListener(_onSettingsChanged);
  }

  final NokDatabase db;
  final SettingsStore settings;
  final String documentsDir;
  final String artDir;

  List<Track> _tracks = [];
  Map<String, Track> _byId = {};
  List<Album> _albums = [];
  List<ArtistGroup> _artists = [];
  List<GenreGroup> _genres = [];
  List<FolderGroup> _folders = [];
  List<Playlist> _playlists = [];
  Set<String> _favorites = {};
  bool _scanning = false;
  String? lastScanSummary;
  final List<StreamSubscription<FileSystemEvent>> _watchers = [];
  Timer? _watchDebounce;
  Timer? _settingsDebounce;

  /// Index filters the stored catalog was built with, kept in the database so a
  /// restart cannot hide a settings change. Only the duration floor also needs
  /// every tag re-read; the size and video filters are re-applied by any scan.
  static const _durationKey = 'library.indexedMinDurationSec';
  static const _filterKey = 'library.indexedFilters';
  String _viewPrint = '';

  String _indexPrint() => '${settings.minSizeKb}|${settings.includeVideos}';

  /// True when the catalog was indexed with different filters than the ones
  /// selected now, so a scan is due.
  bool get _filtersStale =>
      db.kvGet(_durationKey) != '${settings.minDurationSec}' || db.kvGet(_filterKey) != _indexPrint();

  List<Track> get tracks => _tracks;
  List<Track> get videos => _tracks.where((t) => t.isVideo).toList();
  List<Album> get albums => _albums;
  List<ArtistGroup> get artists => _artists;
  List<GenreGroup> get genres => _genres;
  List<FolderGroup> get folders => _folders;
  List<Playlist> get playlists => _playlists;
  bool get scanning => _scanning;
  bool isFavorite(String id) => _favorites.contains(id);
  Track? byId(String id) => _byId[id];

  /// Folders always indexed: the app's Documents folder (exposed to the iOS
  /// Files app) and its Imported/Downloads subfolders, plus user folders.
  List<String> get roots => {documentsDir, ...settings.libraryFolders, ...settings.watchFolders}.toList();

  void loadFromDb() {
    _rebuild(db.allTracks());
    _playlists = db.playlists();
    _favorites = db.favoriteIds();
    notifyListeners();
  }

  Future<IndexResult?> rescan() async {
    if (_scanning) return null;
    _scanning = true;
    notifyListeners();
    var completed = false;
    try {
      final known = Map.fromEntries(db.trackMtimes().entries.where((e) => e.key.startsWith('local:')));
      // An unchanged mtime only says the file is the same; it says nothing
      // about whether the file still passes the *current* filters. When the
      // duration floor changed, every tag must be read again so tracks that
      // are now too short get dropped. `known` is still passed so the scan can
      // also report files deleted from disk while the filters were changed.
      final minDuration = '${settings.minDurationSec}';
      // Only the duration floor forces tag re-reads. The size check runs before
      // the mtime shortcut and excluded videos are simply not seen, so those
      // two filters are applied correctly by any scan.
      final sameDuration = db.kvGet(_durationKey) == minDuration;
      final r = await runIndexer(IndexOptions(
        roots: roots,
        excluded: settings.excludedFolders,
        artDir: artDir,
        minDurationSec: settings.minDurationSec,
        minSizeKb: settings.minSizeKb,
        includeVideos: settings.includeVideos,
        known: known,
        forceRetag: !sameDuration,
      ));
      if (r.added.isNotEmpty) db.upsertTracks(r.added);
      if (r.removedIds.isNotEmpty) db.deleteTracks(r.removedIds);
      db.kvSet(_durationKey, minDuration);
      db.kvSet(_filterKey, _indexPrint());
      _viewPrint = _computeViewPrint();
      lastScanSummary = '${r.added.length} new/updated · ${r.removedIds.length} removed · ${r.unchanged} unchanged · ${r.skipped} filtered';
      completed = true;
      _rebuild(db.allTracks());
      return r;
    } finally {
      _scanning = false;
      notifyListeners();
      // A settings change that arrived mid-scan was refused by the guard above;
      // run again so the library never keeps the old filters.
      if (completed && _filtersStale) {
        _settingsDebounce?.cancel();
        _settingsDebounce = Timer(const Duration(milliseconds: 300), rescan);
      }
    }
  }

  String _computeViewPrint() => [
        settings.filterDuplicates,
        settings.extractFeat,
        ...settings.artistSeparators,
        ...settings.genreSeparators,
      ].join('\u0000');

  /// Grouping settings (duplicates, feat., separators) never change what is
  /// indexed, so a rebuild is enough; the duration floor needs a real rescan.
  void _onSettingsChanged() {
    final view = _computeViewPrint();
    if (view != _viewPrint) {
      _viewPrint = view;
      _rebuild(db.allTracks());
      notifyListeners();
    }
    if (_filtersStale) {
      _settingsDebounce?.cancel();
      _settingsDebounce = Timer(const Duration(milliseconds: 800), rescan);
    }
  }

  /// Copies picked files into Documents/Imported and indexes them.
  Future<int> importFiles(List<String> paths) async {
    final dest = Directory(p.join(documentsDir, 'Imported'))..createSync(recursive: true);
    var n = 0;
    for (final src in paths) {
      try {
        final target = File(p.join(dest.path, p.basename(src)));
        if (!target.existsSync()) await File(src).copy(target.path);
        n++;
      } catch (_) {}
    }
    await rescan();
    return n;
  }

  /// Watch folders: Documents (+ user watch folders) are monitored and
  /// re-indexed incrementally, debounced.
  void startWatching() {
    for (final w in _watchers) {
      w.cancel();
    }
    _watchers.clear();
    for (final r in {documentsDir, ...settings.watchFolders}) {
      try {
        final d = Directory(r);
        if (!d.existsSync() || !FileSystemEntity.isWatchSupported) continue;
        _watchers.add(d.watch(recursive: true).listen((_) {
          _watchDebounce?.cancel();
          _watchDebounce = Timer(const Duration(seconds: 3), rescan);
        }));
      } catch (_) {}
    }
  }

  void _rebuild(List<Track> all) {
    final parser = ArtistParser(separators: settings.artistSeparators, extractFeat: settings.extractFeat);
    var list = all;
    if (settings.filterDuplicates) list = dedupe(list);
    _tracks = list;
    _byId = {for (final t in list) t.id: t};
    // Albums (multi-disc aware; same-name albums kept apart by album artist/folder).
    final albumMap = groupBy(list.where((t) => !t.isVideo), (Track t) => t.albumKey);
    _albums = [
      for (final e in albumMap.entries)
        Album(
          e.key,
          e.value.first.displayAlbum,
          e.value.first.effectiveAlbumArtist.isEmpty ? 'Unknown artist' : e.value.first.effectiveAlbumArtist,
          e.value.sorted((a, b) {
            final d = (a.discNo ?? 1).compareTo(b.discNo ?? 1);
            if (d != 0) return d;
            final n = (a.trackNo ?? 0).compareTo(b.trackNo ?? 0);
            return n != 0 ? n : a.title.compareTo(b.title);
          }),
        ),
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final artistMap = <String, List<Track>>{};
    for (final t in list) {
      final names = parser.split(t.artist, title: t.title);
      for (final n in names.isEmpty ? ['Unknown artist'] : names) {
        artistMap.putIfAbsent(n, () => []).add(t);
      }
    }
    _artists = [for (final e in artistMap.entries) ArtistGroup(e.key, e.value)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final genreMap = <String, List<Track>>{};
    for (final t in list) {
      final gs = splitGenres(t.genre, settings.genreSeparators);
      for (final g in gs.isEmpty ? ['Unknown genre'] : gs) {
        genreMap.putIfAbsent(g, () => []).add(t);
      }
    }
    _genres = [for (final e in genreMap.entries) GenreGroup(e.key, e.value)]..sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
    final folderMap = groupBy(list.where((t) => t.isLocal), (Track t) => t.folder);
    _folders = [for (final e in folderMap.entries) FolderGroup(e.key, e.value)]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<Track> sorted(List<Track> input, TrackSort sort, {bool desc = false}) {
    // One query for the whole list: the comparator used to run COUNT(*) per
    // comparison (n log n queries) and could freeze the UI on large libraries.
    final plays = sort == TrackSort.mostPlayed ? db.playCounts() : const <String, int>{};
    int cmp(Track a, Track b) {
      switch (sort) {
        case TrackSort.title:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case TrackSort.artist:
          return a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
        case TrackSort.album:
          return a.album.toLowerCase().compareTo(b.album.toLowerCase());
        case TrackSort.year:
          return (a.year ?? 0).compareTo(b.year ?? 0);
        case TrackSort.dateAdded:
          return a.dateAdded.compareTo(b.dateAdded);
        case TrackSort.duration:
          return a.durationMs.compareTo(b.durationMs);
        case TrackSort.size:
          return a.sizeBytes.compareTo(b.sizeBytes);
        case TrackSort.mostPlayed:
          return (plays[a.id] ?? 0).compareTo(plays[b.id] ?? 0);
        case TrackSort.filename:
          return p.basename(a.uri).compareTo(p.basename(b.uri));
      }
    }

    final out = [...input]..sort(cmp);
    return desc ? out.reversed.toList() : out;
  }

  /// Typo-tolerant search: FTS5 prefix matches first, then fuzzy fallback.
  List<Track> search(String q) {
    final query = q.trim();
    if (query.isEmpty) return const [];
    final ids = db.searchIds(query);
    final out = <Track>[for (final id in ids) if (_byId[id] != null) _byId[id]!];
    if (out.length < 25) {
      final have = out.map((t) => t.id).toSet();
      for (final t in _tracks) {
        if (have.contains(t.id)) continue;
        if (fuzzyContains('${t.title} ${t.artist} ${t.album} ${p.basename(t.uri)} ${t.lyrics ?? ''}', query)) out.add(t);
        if (out.length > 200) break;
      }
    }
    return out;
  }

  // ---- favourites & playlists ----
  void toggleFavorite(Track t) {
    final fav = !_favorites.contains(t.id);
    db.setFavorite(t, fav);
    fav ? _favorites.add(t.id) : _favorites.remove(t.id);
    notifyListeners();
  }

  List<Track> get favoriteTracks => db.favoriteTracks();

  int createPlaylist(String name) {
    final id = db.createPlaylist(name);
    _playlists = db.playlists();
    notifyListeners();
    return id;
  }

  void addToPlaylist(int id, List<Track> tracks) {
    db.addToPlaylist(id, tracks);
    _playlists = db.playlists();
    notifyListeners();
  }

  void renamePlaylist(int id, String name) {
    db.renamePlaylist(id, name);
    _playlists = db.playlists();
    notifyListeners();
  }

  void deletePlaylist(int id) {
    db.deletePlaylist(id);
    _playlists = db.playlists();
    notifyListeners();
  }

  void reorderPlaylist(int id, List<String> ids) {
    db.setPlaylistOrder(id, ids);
    _playlists = db.playlists();
    notifyListeners();
  }

  List<Track> playlistTracks(Playlist pl) {
    final remote = db.playlistRemoteTracks();
    return [for (final id in pl.trackIds) if ((_byId[id] ?? remote[id]) != null) (_byId[id] ?? remote[id])!];
  }

  /// Adds remote (downloaded) tracks to the unified catalog.
  void addCatalogTracks(List<Track> t) {
    db.upsertTracks(t);
    _rebuild(db.allTracks());
    notifyListeners();
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    _settingsDebounce?.cancel();
    for (final w in _watchers) {
      w.cancel();
    }
    super.dispose();
  }
}
