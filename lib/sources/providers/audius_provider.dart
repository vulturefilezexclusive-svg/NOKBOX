import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../../audio/audio_backend.dart';
import '../../data/models.dart';
import '../source_provider.dart';

/// Audius open API (https://docs.audius.co/api). Streaming is permitted for
/// music players under the API Terms; downloads only when the artist made
/// the track downloadable (official /download endpoint).
class AudiusProvider extends SourceProvider {
  AudiusProvider({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  String? _host;
  static const _app = 'NOKBOX';

  @override
  String get id => SourceIds.audius;
  @override
  String get name => 'Audius';
  @override
  String get tagline => 'Independent hip hop & electronic, artist-uploaded';
  @override
  IconData get icon => Icons.graphic_eq_rounded;
  @override
  Color get brandColor => const Color(0xFFCC0FE0);
  @override
  List<String> get aliases => const ['audius'];
  @override
  String get licenseNote => 'Audius API Terms + Open Music License: streaming allowed with artist attribution; downloads only for tracks the artist marked downloadable.';
  @override
  Uri? officialPage(Track track) => track.extra['permalink'] == null ? null : Uri.parse('https://audius.co${track.extra['permalink']}');

  Future<String> _base() async {
    if (_host != null) return _host!;
    try {
      final r = await _http.get(Uri.parse('https://api.audius.co'), headers: {'User-Agent': nokUserAgent});
      final hosts = (jsonDecode(r.body)['data'] as List).cast<String>();
      _host = hosts.first;
    } catch (_) {
      _host = 'https://discoveryprovider.audius.co';
    }
    return _host!;
  }

  Future<List<Track>> _tracks(String path, Map<String, String> q) async {
    final base = await _base();
    final uri = Uri.parse('$base/v1$path').replace(queryParameters: {...q, 'app_name': _app});
    final r = await _http.get(uri, headers: {'User-Agent': nokUserAgent});
    if (r.statusCode != 200) throw Exception('Audius ${r.statusCode}');
    final data = jsonDecode(r.body)['data'] as List;
    return [for (final j in data) _toTrack(Map<String, dynamic>.from(j as Map))];
  }

  Track _toTrack(Map<String, dynamic> j) {
    final art = j['artwork'] as Map?;
    final downloadable = j['is_downloadable'] == true || (j['download'] is Map && j['download']['is_downloadable'] == true);
    return Track(
      id: '${SourceIds.audius}:${j['id']}',
      uri: 'https://audius.co${j['permalink'] ?? ''}',
      source: SourceIds.audius,
      remoteId: j['id'] as String,
      title: j['title'] as String? ?? '',
      artist: (j['user'] as Map?)?['name'] as String? ?? '',
      album: 'Audius',
      genre: j['genre'] as String? ?? '',
      durationMs: ((j['duration'] as num?) ?? 0).toInt() * 1000,
      artUri: art?['480x480'] as String? ?? art?['150x150'] as String?,
      isrc: j['isrc'] as String?,
      download: downloadable ? DownloadCapability.allowed : DownloadCapability.none,
      extra: {'permalink': j['permalink'], 'plays': j['play_count']},
    );
  }

  @override
  Future<List<FeedSection>> browse() async {
    final sections = <FeedSection>[];
    Future<void> add(String title, String path, Map<String, String> q, {FeedLayout layout = FeedLayout.carousel}) async {
      try {
        final t = await _tracks(path, q);
        if (t.isNotEmpty) sections.add(FeedSection(title: title, items: t.take(25).toList(), layout: layout));
      } catch (_) {}
    }

    await add('Trending Hip-Hop/Rap', '/tracks/trending', {'genre': 'Hip-Hop/Rap', 'time': 'week'});
    await add('Trending R&B/Soul', '/tracks/trending', {'genre': 'R&B/Soul', 'time': 'week'});
    await add('Underground Trending', '/tracks/trending/underground', {}, layout: FeedLayout.list);
    await add('Trending This Month', '/tracks/trending', {'time': 'month'});
    return sections;
  }

  @override
  Future<List<Track>> search(String query) => _tracks('/tracks/search', {'query': query});

  @override
  Future<StreamInfo> resolveStream(Track track, {bool video = false}) async {
    final base = await _base();
    return StreamInfo('$base/v1/tracks/${track.remoteId}/stream?app_name=$_app', headers: {'User-Agent': nokUserAgent});
  }

  @override
  DownloadCapability downloadCapability(Track track) => track.download;

  @override
  Future<StreamInfo?> resolveDownload(Track track) async {
    if (track.download != DownloadCapability.allowed) return null;
    final base = await _base();
    return StreamInfo('$base/v1/tracks/${track.remoteId}/download?app_name=$_app', headers: {'User-Agent': nokUserAgent});
  }
}
