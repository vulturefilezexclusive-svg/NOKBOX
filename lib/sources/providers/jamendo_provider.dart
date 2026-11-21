import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../../audio/audio_backend.dart';
import '../../core/settings.dart';
import '../../data/models.dart';
import '../source_provider.dart';

/// Jamendo API v3 (https://developer.jamendo.com/v3.0). Free client id for
/// non-commercial use. Each track carries `audiodownload_allowed`.
class JamendoProvider extends SourceProvider {
  JamendoProvider(this.settings, {http.Client? client}) : _http = client ?? http.Client();
  final SettingsStore settings;
  final http.Client _http;

  @override
  String get id => SourceIds.jamendo;
  @override
  String get name => 'Jamendo';
  @override
  String get tagline => 'Creative Commons music, free downloads where allowed';
  @override
  IconData get icon => Icons.library_music_rounded;
  @override
  Color get brandColor => const Color(0xFFF7385C);
  @override
  List<String> get aliases => const ['jamendo'];
  @override
  String get licenseNote => 'Jamendo API is free for non-commercial use. Downloads only when audiodownload_allowed is true; CC licence terms apply.';
  @override
  String? get setupHint => settings.jamendoClientId.isEmpty ? 'Paste a free Jamendo client_id (devportal.jamendo.com) in Settings › Sources › Jamendo.' : null;

  Future<List<Track>> _tracks(Map<String, String> q) async {
    if (setupHint != null) throw ProviderSetupRequired(setupHint!);
    final uri = Uri.https('api.jamendo.com', '/v3.0/tracks/', {
      'client_id': settings.jamendoClientId,
      'format': 'json',
      'limit': '30',
      'audioformat': 'mp32',
      'include': 'musicinfo licenses',
      ...q,
    });
    final r = await _http.get(uri, headers: {'User-Agent': nokUserAgent});
    final body = jsonDecode(r.body) as Map;
    return [
      for (final j in (body['results'] as List? ?? const []))
        Track(
          id: '${SourceIds.jamendo}:${j['id']}',
          uri: j['shareurl'] as String? ?? '',
          source: SourceIds.jamendo,
          remoteId: '${j['id']}',
          title: j['name'] as String? ?? '',
          artist: j['artist_name'] as String? ?? '',
          album: j['album_name'] as String? ?? '',
          durationMs: ((j['duration'] as num?) ?? 0).toInt() * 1000,
          artUri: j['image'] as String?,
          download: j['audiodownload_allowed'] == true ? DownloadCapability.allowed : DownloadCapability.none,
          extra: {'audio': j['audio'], 'download': j['audiodownload'], 'license': j['license_ccurl']},
        ),
    ];
  }

  @override
  Future<List<FeedSection>> browse() async => [
        FeedSection(title: 'Hip Hop · Popular this week', items: await _tracks({'tags': 'hiphop', 'order': 'popularity_week'})),
        FeedSection(title: 'Rap · New', items: await _tracks({'tags': 'rap', 'order': 'releasedate_desc'}), layout: FeedLayout.list),
        FeedSection(title: 'R&B / Soul', items: await _tracks({'tags': 'rnb', 'order': 'popularity_month'})),
      ];

  @override
  Future<List<Track>> search(String query) => _tracks({'search': query});

  @override
  Future<StreamInfo> resolveStream(Track track, {bool video = false}) async => StreamInfo(track.extra['audio'] as String);

  @override
  DownloadCapability downloadCapability(Track track) => track.download;

  @override
  Future<StreamInfo?> resolveDownload(Track track) async {
    final d = track.extra['download'] as String?;
    return (track.download == DownloadCapability.allowed && d != null && d.isNotEmpty) ? StreamInfo(d) : null;
  }
}
