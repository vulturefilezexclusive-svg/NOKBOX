import 'dart:convert';

/// Where a track comes from. `local` = on-device file.
class SourceIds {
  static const local = 'local';
  static const youtube = 'youtube';
  static const audius = 'audius';
  static const audiomack = 'audiomack';
  static const jamendo = 'jamendo';
  static const podcast = 'podcast';
  static const radio = 'radio';
  static const archive = 'archive';
  static const custom = 'custom';
}

/// Download permission declared by a provider for a track.
enum DownloadCapability {
  /// CC / royalty-free / own files / artist-enabled via official endpoint.
  allowed,

  /// Purchases or free downloads only via the service's official page.
  viaOfficialPage,

  /// Stream only.
  none,
}

class Track {
  Track({
    required this.id,
    required this.uri,
    required this.title,
    this.source = SourceIds.local,
    this.remoteId,
    this.artist = '',
    this.album = '',
    this.albumArtist = '',
    this.genre = '',
    this.year,
    this.trackNo,
    this.discNo,
    this.durationMs = 0,
    this.sizeBytes = 0,
    this.bitrate,
    this.sampleRate,
    this.format = '',
    this.artUri,
    this.isrc,
    this.mbid,
    this.folder = '',
    this.dateAdded = 0,
    this.isVideo = false,
    this.lyrics,
    this.download = DownloadCapability.none,
    this.extra = const {},
  });

  /// Stable id: for local files `local:<path>`, for remote `<source>:<remoteId>`.
  final String id;

  /// File path or remote page URL. Streams are resolved lazily by providers.
  final String uri;
  final String source;
  final String? remoteId;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String genre;
  final int? year;
  final int? trackNo;
  final int? discNo;
  final int durationMs;
  final int sizeBytes;
  final int? bitrate;
  final int? sampleRate;
  final String format;
  final String? artUri;
  final String? isrc;
  final String? mbid;
  final String folder;
  final int dateAdded;
  final bool isVideo;
  final String? lyrics;
  final DownloadCapability download;
  final Map<String, dynamic> extra;

  bool get isLocal => source == SourceIds.local;
  Duration get duration => Duration(milliseconds: durationMs);
  String get displayArtist => artist.isEmpty ? 'Unknown artist' : artist;
  String get displayAlbum => album.isEmpty ? 'Unknown album' : album;
  String get effectiveAlbumArtist => albumArtist.isNotEmpty ? albumArtist : artist;

  /// Album identity: same-name albums by different album artists (or in
  /// different folders when no album artist) are kept apart.
  String get albumKey =>
      '${album.toLowerCase()}\u0000${(albumArtist.isNotEmpty ? albumArtist : (isLocal ? folder : artist)).toLowerCase()}';

  Track copyWith({
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    String? genre,
    int? year,
    int? durationMs,
    String? artUri,
    String? lyrics,
    String? uri,
    DownloadCapability? download,
    Map<String, dynamic>? extra,
  }) =>
      Track(
        id: id,
        uri: uri ?? this.uri,
        title: title ?? this.title,
        source: source,
        remoteId: remoteId,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        albumArtist: albumArtist ?? this.albumArtist,
        genre: genre ?? this.genre,
        year: year ?? this.year,
        trackNo: trackNo,
        discNo: discNo,
        durationMs: durationMs ?? this.durationMs,
        sizeBytes: sizeBytes,
        bitrate: bitrate,
        sampleRate: sampleRate,
        format: format,
        artUri: artUri ?? this.artUri,
        isrc: isrc,
        mbid: mbid,
        folder: folder,
        dateAdded: dateAdded,
        isVideo: isVideo,
        lyrics: lyrics ?? this.lyrics,
        download: download ?? this.download,
        extra: extra ?? this.extra,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'uri': uri,
        'title': title,
        'source': source,
        'remoteId': remoteId,
        'artist': artist,
        'album': album,
        'albumArtist': albumArtist,
        'genre': genre,
        'year': year,
        'trackNo': trackNo,
        'discNo': discNo,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
        'bitrate': bitrate,
        'sampleRate': sampleRate,
        'format': format,
        'artUri': artUri,
        'isrc': isrc,
        'mbid': mbid,
        'folder': folder,
        'dateAdded': dateAdded,
        'isVideo': isVideo,
        'download': download.name,
        'extra': extra,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        uri: j['uri'] as String? ?? '',
        title: j['title'] as String? ?? '',
        source: j['source'] as String? ?? SourceIds.local,
        remoteId: j['remoteId'] as String?,
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String? ?? '',
        albumArtist: j['albumArtist'] as String? ?? '',
        genre: j['genre'] as String? ?? '',
        year: (j['year'] as num?)?.toInt(),
        trackNo: (j['trackNo'] as num?)?.toInt(),
        discNo: (j['discNo'] as num?)?.toInt(),
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        bitrate: (j['bitrate'] as num?)?.toInt(),
        sampleRate: (j['sampleRate'] as num?)?.toInt(),
        format: j['format'] as String? ?? '',
        artUri: j['artUri'] as String?,
        isrc: j['isrc'] as String?,
        mbid: j['mbid'] as String?,
        folder: j['folder'] as String? ?? '',
        dateAdded: (j['dateAdded'] as num?)?.toInt() ?? 0,
        isVideo: j['isVideo'] as bool? ?? false,
        download: DownloadCapability.values.firstWhere(
          (d) => d.name == j['download'],
          orElse: () => DownloadCapability.none,
        ),
        extra: Map<String, dynamic>.from(j['extra'] as Map? ?? const {}),
      );

  String encode() => jsonEncode(toJson());
  static Track decode(String s) => Track.fromJson(jsonDecode(s) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) => other is Track && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class Album {
  Album(this.key, this.title, this.artist, this.tracks);
  final String key;
  final String title;
  final String artist;
  final List<Track> tracks;
  String? get artUri => tracks.map((t) => t.artUri).firstWhere((a) => a != null, orElse: () => null);
  int? get year => tracks.map((t) => t.year).firstWhere((y) => y != null, orElse: () => null);
  int get durationMs => tracks.fold(0, (a, t) => a + t.durationMs);
  Set<int> get discs => tracks.map((t) => t.discNo ?? 1).toSet();
}

class ArtistGroup {
  ArtistGroup(this.name, this.tracks);
  final String name;
  final List<Track> tracks;
  String? get artUri => tracks.map((t) => t.artUri).firstWhere((a) => a != null, orElse: () => null);
  int get albumCount => tracks.map((t) => t.albumKey).toSet().length;
}

class GenreGroup {
  GenreGroup(this.name, this.tracks);
  final String name;
  final List<Track> tracks;
}

class FolderGroup {
  FolderGroup(this.path, this.tracks);
  final String path;
  final List<Track> tracks;
  String get name => path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull ?? path;
}

class Playlist {
  Playlist({required this.id, required this.name, required this.trackIds, this.createdAt = 0, this.artUri, this.description = ''});
  final int id;
  final String name;
  final List<String> trackIds;
  final int createdAt;
  final String? artUri;
  final String description;
}
