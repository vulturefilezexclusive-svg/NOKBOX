import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../../audio/audio_backend.dart';
import '../../core/settings.dart';
import '../../data/models.dart';
import '../source_provider.dart';

/// Audiomack Data API (https://audiomack.com/data-api/docs), OAuth 1.0a.
/// Audiomack issues API apps on request: until the user pastes the
/// consumer key/secret in Settings › Sources this provider only shows a
/// setup card. Downloads stay disabled until Audiomack gives written OK
/// (toggle `audiomackDownloadsApproved`), and even then go through the
/// official page.
class AudiomackProvider extends SourceProvider {
  AudiomackProvider(this.settings, {http.Client? client}) : _http = client ?? http.Client();
  final SettingsStore settings;
  final http.Client _http;
  static const _base = 'https://api.audiomack.com/v1';

  @override
  String get id => SourceIds.audiomack;
  @override
  String get name => 'Audiomack';
  @override
  String get tagline => 'Hip hop, Afrobeats, R&B, mixtapes';
  @override
  IconData get icon => Icons.album_rounded;
  @override
  Color get brandColor => const Color(0xFFFFA200);
  @override
  List<String> get aliases => const ['audiomack', 'am'];
  @override
  String get licenseNote => 'Requires an Audiomack API key (OAuth 1.0a, apps approved on request). No scraping. Downloads disabled until Audiomack approves in writing.';
  @override
  String? get setupHint => settings.audiomackConsumerKey.isEmpty
      ? 'Add your Audiomack API consumer key & secret in Settings › Sources › Audiomack. Request one at audiomack.com/data-api/docs.'
      : null;
  @override
  Uri? officialPage(Track track) => track.extra['url'] == null ? null : Uri.parse(track.extra['url'] as String);

  /// RFC 5849 HMAC-SHA1 signature (consumer-only / two-legged).
  static String oauthHeader(String method, Uri uri, String key, String secret, {String? nonce, int? timestamp}) {
    String enc(String s) => Uri.encodeComponent(s).replaceAll('+', '%20').replaceAll('*', '%2A').replaceAll('%7E', '~');
    final oauth = {
      'oauth_consumer_key': key,
      'oauth_nonce': nonce ?? List.generate(16, (_) => Random.secure().nextInt(16).toRadixString(16)).join(),
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': '${timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'oauth_version': '1.0',
    };
    final params = {...uri.queryParameters, ...oauth};
    final keys = params.keys.toList()..sort();
    final paramStr = keys.map((k) => '${enc(k)}=${enc(params[k]!)}').join('&');
    final baseUrl = uri.replace(query: '').toString().replaceAll('?', '');
    final baseStr = '${method.toUpperCase()}&${enc(baseUrl)}&${enc(paramStr)}';
    final sig = base64.encode(Hmac(sha1, utf8.encode('${enc(secret)}&')).convert(utf8.encode(baseStr)).bytes);
    final all = {...oauth, 'oauth_signature': sig};
    return 'OAuth ${all.entries.map((e) => '${enc(e.key)}="${enc(e.value)}"').join(', ')}';
  }

  Future<dynamic> _get(String path, [Map<String, String> q = const {}]) async {
    final key = settings.audiomackConsumerKey, secret = settings.audiomackConsumerSecret;
    if (key.isEmpty) throw ProviderSetupRequired(setupHint!);
    final uri = Uri.parse('$_base$path').replace(queryParameters: q.isEmpty ? null : q);
    final r = await _http.get(uri, headers: {'Authorization': oauthHeader('GET', uri, key, secret), 'User-Agent': nokUserAgent});
    if (r.statusCode != 200) throw Exception('Audiomack ${r.statusCode}');
    return jsonDecode(r.body);
  }

  Track _toTrack(Map<String, dynamic> j) => Track(
        id: '${SourceIds.audiomack}:${j['id']}',
        uri: 'https://audiomack.com/${j['uploader']?['url_slug'] ?? ''}/song/${j['url_slug'] ?? ''}',
        source: SourceIds.audiomack,
        remoteId: '${j['id']}',
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String? ?? 'Audiomack',
        genre: j['genre'] as String? ?? '',
        durationMs: (int.tryParse('${j['duration'] ?? 0}') ?? 0) * 1000,
        artUri: j['image'] as String?,
        isrc: j['isrc'] as String?,
        download: settings.audiomackDownloadsApproved ? DownloadCapability.viaOfficialPage : DownloadCapability.none,
        extra: {'url': 'https://audiomack.com/${j['uploader']?['url_slug'] ?? ''}/song/${j['url_slug'] ?? ''}'},
      );

  List<Track> _list(dynamic body) {
    final res = body is Map ? (body['results'] ?? body['result']) : body;
    if (res is! List) return const [];
    return [for (final j in res) if (j is Map && (j['type'] == null || j['type'] == 'song')) _toTrack(Map<String, dynamic>.from(j))];
  }

  @override
  Future<List<FeedSection>> browse() async {
    if (setupHint != null) throw ProviderSetupRequired(setupHint!);
    final out = <FeedSection>[];
    for (final (title, genre) in [('Trending Rap', 'rap'), ('Trending Afrobeats', 'afrobeats'), ('Trending R&B', 'rnb')]) {
      try {
        final t = _list(await _get('/music/$genre/trending/song'));
        if (t.isNotEmpty) out.add(FeedSection(title: title, items: t));
      } catch (_) {}
    }
    return out;
  }

  @override
  Future<List<Track>> search(String query) async => _list(await _get('/search', {'q': query, 'show': 'songs', 'limit': '30'}));

  @override
  Future<StreamInfo> resolveStream(Track track, {bool video = false}) async {
    final body = await _get('/music/play/${track.remoteId}');
    final url = body is Map ? (body['signedUrl'] ?? body['results']?['signedUrl'] ?? body['url']) : body;
    if (url is! String) throw Exception('Audiomack stream unavailable');
    return StreamInfo(url);
  }

  @override
  DownloadCapability downloadCapability(Track track) =>
      settings.audiomackDownloadsApproved ? DownloadCapability.viaOfficialPage : DownloadCapability.none;

  @override
  Future<StreamInfo?> resolveDownload(Track track) async => null;
}
