import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../../audio/audio_backend.dart';
import '../../data/models.dart';
import '../source_provider.dart';

/// Internet radio via the community Radio Browser directory
/// (https://api.radio-browser.info). Stream only.
class RadioProvider extends SourceProvider {
  RadioProvider({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  static const _host = 'https://all.api.radio-browser.info';

  @override
  String get id => SourceIds.radio;
  @override
  String get name => 'Radio';
  @override
  String get tagline => 'Live hip hop, rap & R&B stations worldwide';
  @override
  IconData get icon => Icons.radio_rounded;
  @override
  Color get brandColor => const Color(0xFF00B894);
  @override
  List<String> get aliases => const ['radio', 'internet radio', 'radio browser', 'stations'];
  @override
  String get licenseNote => 'Station directory from Radio Browser (public domain data). Live streams only, no recording.';

  Future<List<Track>> _stations(String path, Map<String, String> q) async {
    final uri = Uri.parse('$_host/json/stations$path').replace(queryParameters: {'hidebroken': 'true', 'limit': '40', 'order': 'clickcount', 'reverse': 'true', ...q});
    final r = await _http.get(uri, headers: {'User-Agent': nokUserAgent});
    final list = jsonDecode(r.body) as List;
    return [
      for (final s in list)
        Track(
          id: 'radio:${s['stationuuid']}',
          uri: s['url_resolved'] as String? ?? s['url'] as String,
          source: SourceIds.radio,
          remoteId: s['stationuuid'] as String,
          title: (s['name'] as String? ?? '').trim(),
          artist: [s['country'], s['codec'], if ((s['bitrate'] ?? 0) != 0) '${s['bitrate']}kbps'].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
          album: 'Live radio',
          genre: s['tags'] as String? ?? '',
          artUri: (s['favicon'] as String?)?.isEmpty ?? true ? null : s['favicon'] as String,
          extra: {'live': true},
        ),
    ];
  }

  @override
  Future<List<FeedSection>> browse() async => [
        FeedSection(title: 'Top Hip Hop Stations', items: await _stations('/bytag/hip hop', {})),
        FeedSection(title: 'Rap', items: await _stations('/bytag/rap', {}), layout: FeedLayout.list),
        FeedSection(title: 'R&B', items: await _stations('/bytag/rnb', {})),
      ];

  @override
  Future<List<Track>> search(String query) => _stations('/search', {'name': query});

  @override
  Future<StreamInfo> resolveStream(Track track, {bool video = false}) async {
    // Count the click as Radio Browser asks clients to (best effort).
    _http.get(Uri.parse('$_host/json/url/${track.remoteId}'), headers: {'User-Agent': nokUserAgent}).ignore();
    return StreamInfo(track.uri);
  }

  @override
  DownloadCapability downloadCapability(Track track) => DownloadCapability.none;
}
