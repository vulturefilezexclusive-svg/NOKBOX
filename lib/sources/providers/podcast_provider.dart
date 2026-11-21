import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:xml/xml.dart';

import '../../audio/audio_backend.dart';
import '../../core/settings.dart';
import '../../data/models.dart';
import '../source_provider.dart';

/// Podcasts: discovery via the iTunes Search API (no key) or Podcast Index
/// (optional key), playback/downloads straight from the show's RSS feed
/// (podcasts are published for download by design).
class PodcastProvider extends SourceProvider {
  PodcastProvider(this.settings, {http.Client? client}) : _http = client ?? http.Client();
  final SettingsStore settings;
  final http.Client _http;

  @override
  String get id => SourceIds.podcast;
  @override
  String get name => 'Podcasts';
  @override
  String get tagline => 'Hip hop podcasts, interviews, culture';
  @override
  IconData get icon => Icons.podcasts_rounded;
  @override
  Color get brandColor => const Color(0xFF8E44EC);
  @override
  List<String> get aliases => const ['podcast', 'podcasts', 'podcast index', 'rss'];
  @override
  String get licenseNote => 'Episodes stream/download from the publisher\'s public RSS feed. Directory: iTunes Search API or Podcast Index.';

  Future<List<Track>> _searchShows(String term) async {
    if (settings.podcastIndexKey.isNotEmpty) {
      try {
        return await _podcastIndex(term);
      } catch (_) {}
    }
    final uri = Uri.https('itunes.apple.com', '/search', {'media': 'podcast', 'term': term, 'limit': '30'});
    final r = await _http.get(uri);
    final res = (jsonDecode(r.body) as Map)['results'] as List? ?? const [];
    return [
      for (final j in res)
        if (j['feedUrl'] != null)
          Track(
            id: 'podcast:show:${j['collectionId']}',
            uri: j['feedUrl'] as String,
            source: SourceIds.podcast,
            remoteId: '${j['collectionId']}',
            title: j['collectionName'] as String? ?? '',
            artist: j['artistName'] as String? ?? '',
            album: 'Podcast',
            genre: j['primaryGenreName'] as String? ?? '',
            artUri: j['artworkUrl600'] as String? ?? j['artworkUrl100'] as String?,
            extra: {'collection': true, 'feed': j['feedUrl']},
          ),
    ];
  }

  Future<List<Track>> _podcastIndex(String term) async {
    final ts = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final auth = sha1.convert(utf8.encode('${settings.podcastIndexKey}${settings.podcastIndexSecret}$ts')).toString();
    final r = await _http.get(Uri.https('api.podcastindex.org', '/api/1.0/search/byterm', {'q': term}), headers: {
      'User-Agent': nokUserAgent,
      'X-Auth-Key': settings.podcastIndexKey,
      'X-Auth-Date': ts,
      'Authorization': auth,
    });
    final feeds = (jsonDecode(r.body) as Map)['feeds'] as List? ?? const [];
    return [
      for (final f in feeds)
        Track(
          id: 'podcast:show:${f['id']}',
          uri: f['url'] as String,
          source: SourceIds.podcast,
          remoteId: '${f['id']}',
          title: f['title'] as String? ?? '',
          artist: f['author'] as String? ?? '',
          album: 'Podcast',
          artUri: f['artwork'] as String? ?? f['image'] as String?,
          extra: {'collection': true, 'feed': f['url']},
        ),
    ];
  }

  @override
  Future<List<FeedSection>> browse() async => [
        FeedSection(title: 'Hip Hop Podcasts', items: await _searchShows('hip hop')),
        FeedSection(title: 'Rap Culture & Interviews', items: await _searchShows('rap interviews'), layout: FeedLayout.list),
        FeedSection(title: 'R&B Talk', items: await _searchShows('r&b podcast')),
      ];

  @override
  Future<List<Track>> search(String query) => _searchShows(query);

  @override
  Future<List<Track>> expand(Track collection) async {
    final r = await _http.get(Uri.parse(collection.extra['feed'] as String? ?? collection.uri), headers: {'User-Agent': nokUserAgent});
    return parseRss(utf8.decode(r.bodyBytes, allowMalformed: true), fallbackArt: collection.artUri, showName: collection.title);
  }

  /// Parses podcast RSS into episode tracks (also used by Custom URL feeds).
  static List<Track> parseRss(String xml, {String? fallbackArt, String showName = ''}) {
    final doc = XmlDocument.parse(xml);
    final channel = doc.findAllElements('channel').firstOrNull;
    final show = channel?.getElement('title')?.innerText ?? showName;
    final chArt = channel?.findElements('itunes:image').firstOrNull?.getAttribute('href') ?? fallbackArt;
    final out = <Track>[];
    for (final item in doc.findAllElements('item')) {
      final enc = item.getElement('enclosure');
      final url = enc?.getAttribute('url');
      if (url == null) continue;
      final durStr = item.findElements('itunes:duration').firstOrNull?.innerText ?? '';
      out.add(Track(
        id: 'podcast:${item.getElement('guid')?.innerText ?? url}',
        uri: url,
        source: SourceIds.podcast,
        remoteId: url,
        title: item.getElement('title')?.innerText.trim() ?? 'Episode',
        artist: show,
        album: show,
        durationMs: _parseDur(durStr) * 1000,
        artUri: item.findElements('itunes:image').firstOrNull?.getAttribute('href') ?? chArt,
        isVideo: (enc?.getAttribute('type') ?? '').startsWith('video'),
        download: DownloadCapability.allowed,
        extra: {'pubDate': item.getElement('pubDate')?.innerText, 'desc': item.getElement('description')?.innerText},
      ));
    }
    return out;
  }

  static int _parseDur(String s) {
    if (s.isEmpty) return 0;
    final parts = s.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    return parts.fold(0, (a, b) => a * 60 + b);
  }

  @override
  Future<StreamInfo> resolveStream(Track track, {bool video = false}) async => StreamInfo(track.uri, isVideo: track.isVideo);

  @override
  DownloadCapability downloadCapability(Track track) => isCollection(track) ? DownloadCapability.none : DownloadCapability.allowed;
}
