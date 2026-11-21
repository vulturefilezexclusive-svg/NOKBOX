import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../../audio/audio_backend.dart';
import '../../data/models.dart';
import '../source_provider.dart';

/// Internet Archive audio, restricted to items carrying a Creative Commons
/// or public-domain licence URL (many mixtape uploads are unlicensed and
/// are therefore excluded).
class ArchiveProvider extends SourceProvider {
  ArchiveProvider({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  @override
  String get id => SourceIds.archive;
  @override
  String get name => 'Internet Archive';
  @override
  String get tagline => 'CC & public-domain recordings, live sets';
  @override
  IconData get icon => Icons.account_balance_rounded;
  @override
  Color get brandColor => const Color(0xFFB0B0B0);
  @override
  List<String> get aliases => const ['archive', 'internet archive', 'archive.org'];
  @override
  String get licenseNote => 'Only items with a Creative Commons or public-domain licence are listed; downloads follow that licence.';

  static const _licensed = '(licenseurl:*creativecommons.org* OR licenseurl:*publicdomain*)';

  Future<List<Track>> _items(String q) async {
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': '($q) AND mediatype:audio AND $_licensed',
      'fl[]': 'identifier,title,creator,licenseurl,downloads',
      'rows': '30',
      'sort[]': 'downloads desc',
      'output': 'json',
    });
    final r = await _http.get(uri, headers: {'User-Agent': nokUserAgent});
    final docs = ((jsonDecode(r.body) as Map)['response']?['docs'] as List?) ?? const [];
    return [
      for (final d in docs)
        Track(
          id: 'archive:item:${d['identifier']}',
          uri: 'https://archive.org/details/${d['identifier']}',
          source: SourceIds.archive,
          remoteId: d['identifier'] as String,
          title: '${d['title'] ?? d['identifier']}',
          artist: d['creator'] is List ? (d['creator'] as List).join(', ') : '${d['creator'] ?? ''}',
          album: 'Internet Archive',
          artUri: 'https://archive.org/services/img/${d['identifier']}',
          extra: {'collection': true, 'license': d['licenseurl']},
        ),
    ];
  }

  @override
  Future<List<FeedSection>> browse() async => [
        FeedSection(title: 'Hip Hop (CC licensed)', items: await _items('subject:"hip hop" OR subject:hiphop')),
        FeedSection(title: 'Rap & Beats', items: await _items('subject:rap OR subject:beats OR subject:instrumental'), layout: FeedLayout.list),
      ];

  @override
  Future<List<Track>> search(String query) => _items(query);

  @override
  Future<List<Track>> expand(Track collection) async {
    final r = await _http.get(Uri.https('archive.org', '/metadata/${collection.remoteId}'), headers: {'User-Agent': nokUserAgent});
    final j = jsonDecode(r.body) as Map;
    final files = (j['files'] as List? ?? const []).where((f) => '${f['format']}'.contains('MP3') || '${f['name']}'.toLowerCase().endsWith('.mp3'));
    return [
      for (final f in files)
        Track(
          id: 'archive:${collection.remoteId}/${f['name']}',
          uri: 'https://archive.org/download/${collection.remoteId}/${Uri.encodeComponent(f['name'] as String)}',
          source: SourceIds.archive,
          remoteId: '${collection.remoteId}/${f['name']}',
          title: '${f['title'] ?? (f['name'] as String).replaceAll('.mp3', '')}',
          artist: '${f['creator'] ?? collection.artist}',
          album: collection.title,
          durationMs: ((double.tryParse('${f['length'] ?? 0}') ?? 0) * 1000).toInt(),
          artUri: collection.artUri,
          download: DownloadCapability.allowed,
          extra: {'license': collection.extra['license']},
        ),
    ];
  }

  @override
  Future<StreamInfo> resolveStream(Track track, {bool video = false}) async => StreamInfo(track.uri);

  @override
  DownloadCapability downloadCapability(Track track) => isCollection(track) ? DownloadCapability.none : DownloadCapability.allowed;
}
