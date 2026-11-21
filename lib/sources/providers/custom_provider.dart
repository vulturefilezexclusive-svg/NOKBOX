import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../../audio/audio_backend.dart';
import '../../data/models.dart';
import '../source_provider.dart';
import 'podcast_provider.dart';

/// Generic provider for a user-typed URL: direct audio/video file, HLS,
/// M3U/PLS playlist, Icecast stream or RSS feed. Stream only unless the
/// URL is an RSS podcast feed (episodes are published for download).
class CustomUrlProvider extends SourceProvider {
  CustomUrlProvider(this.url, {http.Client? client}) : _http = client ?? http.Client();
  final Uri url;
  final http.Client _http;

  @override
  String get id => SourceIds.custom;
  @override
  String get name => url.host.isEmpty ? 'Custom source' : url.host;
  @override
  String get tagline => 'Custom URL · stream only';
  @override
  IconData get icon => Icons.link_rounded;
  @override
  Color get brandColor => const Color(0xFF607D8B);
  @override
  String get licenseNote => 'You are responsible for having rights to stream content from custom URLs. NOKBOX never bypasses DRM or paywalls.';

  static const _mediaExt = ['.mp3', '.aac', '.m4a', '.ogg', '.opus', '.flac', '.wav', '.m3u8', '.mp4', '.webm'];

  Track _single(Uri u, {String? title}) => Track(
        id: 'custom:$u',
        uri: u.toString(),
        source: SourceIds.custom,
        remoteId: u.toString(),
        title: title ?? (u.pathSegments.isEmpty ? u.host : Uri.decodeComponent(u.pathSegments.last)),
        artist: u.host,
        album: 'Custom',
        isVideo: u.path.endsWith('.mp4') || u.path.endsWith('.webm'),
      );

  @override
  Future<List<FeedSection>> browse() async {
    final path = url.path.toLowerCase();
    if (_mediaExt.any(path.endsWith)) {
      return [FeedSection(title: 'Stream', items: [_single(url)], layout: FeedLayout.list)];
    }
    final r = await _http.get(url, headers: {'User-Agent': nokUserAgent});
    final ct = r.headers['content-type'] ?? '';
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (ct.contains('audio/') || ct.contains('video/')) {
      return [FeedSection(title: 'Live stream', items: [_single(url)], layout: FeedLayout.list)];
    }
    if (body.contains('<rss') || body.contains('<feed')) {
      return [FeedSection(title: 'Episodes', items: PodcastProvider.parseRss(body), layout: FeedLayout.list)];
    }
    if (path.endsWith('.m3u') || path.endsWith('.pls') || body.startsWith('#EXTM3U') || body.startsWith('[playlist]')) {
      return [FeedSection(title: 'Playlist', items: parsePlaylist(body, url).map((e) => _single(e.$1, title: e.$2)).toList(), layout: FeedLayout.list)];
    }
    throw const WebFallbackRequired();
  }

  /// Parses M3U / PLS into (url, title) pairs.
  static List<(Uri, String?)> parsePlaylist(String body, Uri base) {
    final out = <(Uri, String?)>[];
    String? pendingTitle;
    for (final raw in const LineSplitter().convert(body)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF')) {
        pendingTitle = line.contains(',') ? line.substring(line.indexOf(',') + 1).trim() : null;
      } else if (line.toLowerCase().startsWith('file')) {
        final v = line.substring(line.indexOf('=') + 1).trim();
        out.add((base.resolve(v), null));
      } else if (line.toLowerCase().startsWith('title') && out.isNotEmpty) {
        final last = out.removeLast();
        out.add((last.$1, line.substring(line.indexOf('=') + 1).trim()));
      } else if (!line.startsWith('#') && !line.startsWith('[') && !line.contains('=')) {
        out.add((base.resolve(line), pendingTitle));
        pendingTitle = null;
      }
    }
    return out;
  }

  @override
  Future<List<Track>> search(String query) async => const [];

  @override
  Future<StreamInfo> resolveStream(Track track, {bool video = false}) async => StreamInfo(track.uri, isVideo: track.isVideo);

  @override
  DownloadCapability downloadCapability(Track track) => track.download;
}

class WebFallbackRequired implements Exception {
  const WebFallbackRequired();
}

/// "Anything else": the service's own website and player shown inside the
/// feed area (stream only; NOKBOX does not extract media from it).
class WebSourceProvider extends SourceProvider {
  WebSourceProvider(this.label, this.home);
  final String label;
  final Uri home;

  @override
  String get id => 'web';
  @override
  String get name => label;
  @override
  String get tagline => 'Opened in the in-app browser · stream only';
  @override
  IconData get icon => Icons.public_rounded;
  @override
  Color get brandColor => const Color(0xFF3D7BFF);
  @override
  String get licenseNote => 'Shown with the service\'s own site and player. No downloads, no extraction.';
  @override
  Uri? get webUrl => home;
  @override
  Future<List<FeedSection>> browse() async => const [];
  @override
  Future<List<Track>> search(String query) async => const [];
  @override
  Future<StreamInfo> resolveStream(Track track, {bool video = false}) => throw UnsupportedError('web source');
  @override
  DownloadCapability downloadCapability(Track track) => DownloadCapability.none;
}

/// Sources that only work by circumventing DRM/paywalls. Never integrated.
class BlockedProvider extends WebSourceProvider {
  BlockedProvider(String label, this.reason) : super(label, Uri());
  final String reason;
  @override
  Uri? get webUrl => null;
  @override
  String get tagline => 'Not supported';
  @override
  IconData get icon => Icons.block_rounded;
  @override
  String get licenseNote => reason;
  @override
  String? get setupHint => reason;
}
