import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../audio/audio_backend.dart';
import '../../core/diagnostics.dart';
import '../../core/settings.dart';
import '../../data/models.dart';
import '../source_provider.dart';
import '../youtube/youtube_account.dart';

/// YouTube: home feed (personalised when signed in), search, playback and
/// downloads. Stream manifests are resolved with several InnerTube clients
/// in order, and each candidate URL is probed before it is handed to mpv.
class YoutubeProvider extends SourceProvider {
  YoutubeProvider(this.settings, this.account, {this.recentHistory});
  final SettingsStore settings;
  final YoutubeAccount account;

  /// Recently played tracks (newest first) for "because you watched" shelves.
  final List<Track> Function()? recentHistory;
  final _yt = yt.YoutubeExplode();

  static final _clients = <(String, yt.YoutubeApiClient, String)>[
    ('android_sdkless', yt.YoutubeApiClient.androidSdkless, 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip'),
    ('android', yt.YoutubeApiClient.android, 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip'),
    ('ios', yt.YoutubeApiClient.ios, 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)'),
    ('tv', yt.YoutubeApiClient.tv, 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version'),
    ('android_vr', yt.YoutubeApiClient.androidVr, 'com.google.android.apps.youtube.vr.oculus/1.62.27 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip'),
    ('safari', yt.YoutubeApiClient.safari, 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)'),
  ];

  @override
  String get id => SourceIds.youtube;
  @override
  String get name => 'YouTube';
  @override
  String get tagline => 'Music videos, freestyles, new drops';
  @override
  IconData get icon => Icons.smart_display_rounded;
  @override
  Color get brandColor => const Color(0xFFFF0000);
  @override
  List<String> get aliases => const ['youtube', 'yt', 'youtube music', 'ytm'];
  @override
  String get licenseNote => '';
  @override
  Uri? officialPage(Track track) => Uri.parse('https://www.youtube.com/watch?v=${track.remoteId}');

  static const _shelves = <(String, String)>[
    ('Trending in Hip Hop', 'new hip hop songs this week'),
    ('Trap Bangers', 'trap music new releases'),
    ('Drill Season', 'new drill music'),
    ('R&B Vibes', 'new r&b songs'),
    ('Freestyles & Cyphers', 'freestyle cypher'),
    ('Underground Picks', 'underground rap new'),
  ];

  // ---------------- Feed ----------------

  @override
  Future<List<FeedSection>> browse() async {
    final out = <FeedSection>[];
    // 1. Real YouTube home (personalised when signed in).
    try {
      out.addAll(await _innertubeFeed('FEwhat_to_watch', account.signedIn ? 'Recommended for you' : 'Recommended'));
    } catch (e) {
      Diag.warn('yt.home', '$e');
    }
    if (account.signedIn) {
      try {
        out.addAll(await _innertubeFeed('FEsubscriptions', 'From your subscriptions'));
      } catch (e) {
        Diag.warn('yt.subs', '$e');
      }
    }
    // 2. "Because you watched": related videos to recent plays.
    final recent = (recentHistory?.call() ?? const <Track>[]).where((t) => t.source == SourceIds.youtube && t.remoteId != null).take(2);
    for (final t in recent) {
      try {
        final v = await _yt.videos.get(t.remoteId!);
        final rel = await _yt.videos.getRelatedVideos(v);
        if (rel != null && rel.isNotEmpty) out.add(FeedSection(title: 'Because you played ${t.title}', items: [for (final r in rel.take(20)) _toTrack(r)]));
      } catch (e) {
        Diag.warn('yt.related', '$e');
      }
    }
    // 3. Artists you play most.
    final artists = <String>{for (final t in recentHistory?.call() ?? const <Track>[]) t.displayArtist}.where((a) => a.isNotEmpty).take(2);
    for (final a in artists) {
      try {
        final items = await search('$a new songs');
        if (items.isNotEmpty) out.add(FeedSection(title: 'More from $a', items: items.take(15).toList()));
      } catch (_) {}
    }
    // 4. Trending music shelves.
    for (final (title, q) in _shelves) {
      if (out.length >= 8) break;
      try {
        final items = await search(q);
        if (items.isNotEmpty) out.add(FeedSection(title: title, items: items.take(15).toList()));
      } catch (e) {
        Diag.warn('yt.shelf', '$e');
      }
    }
    return out;
  }

  Future<List<FeedSection>> _innertubeFeed(String browseId, String title) async {
    final j = await account.innertube('browse', {'browseId': browseId});
    final items = <Track>[];
    final seen = <String>{};
    void walk(dynamic n) {
      if (n is Map) {
        final vr = n['videoRenderer'] ?? n['compactVideoRenderer'] ?? n['gridVideoRenderer'];
        if (vr is Map && vr['videoId'] is String) {
          final t = _fromRenderer(vr);
          if (t != null && seen.add(t.remoteId!)) items.add(t);
          return;
        }
        final lk = n['lockupViewModel'];
        if (lk is Map && lk['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO') {
          final t = _fromLockup(lk);
          if (t != null && seen.add(t.remoteId!)) items.add(t);
          return;
        }
        n.values.forEach(walk);
      } else if (n is List) {
        n.forEach(walk);
      }
    }

    walk(j);
    if (items.isEmpty) return const [];
    final out = <FeedSection>[];
    for (var i = 0; i < items.length && out.length < 3; i += 20) {
      out.add(FeedSection(title: i == 0 ? title : '$title · more', items: items.sublist(i, (i + 20).clamp(0, items.length))));
    }
    return out;
  }

  static String _text(dynamic t) {
    if (t is Map) {
      if (t['simpleText'] is String) return t['simpleText'] as String;
      if (t['runs'] is List) return (t['runs'] as List).map((r) => r['text'] ?? '').join();
      if (t['content'] is String) return t['content'] as String;
    }
    return '';
  }

  static int _parseLen(String s) {
    final parts = s.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    var sec = 0;
    for (final p in parts) {
      sec = sec * 60 + p;
    }
    return sec * 1000;
  }

  Track? _fromRenderer(Map vr) {
    final id = vr['videoId'] as String;
    final title = _text(vr['title']);
    if (title.isEmpty) return null;
    final ch = _text(vr['ownerText'] ?? vr['longBylineText'] ?? vr['shortBylineText']);
    return _make(id, title, ch, _parseLen(_text(vr['lengthText'])));
  }

  Track? _fromLockup(Map lk) {
    final id = lk['contentId'] as String?;
    final md = lk['metadata']?['lockupMetadataViewModel'];
    if (id == null || md is! Map) return null;
    final title = _text(md['title']);
    var ch = '';
    final rows = md['metadata']?['contentMetadataViewModel']?['metadataRows'];
    if (rows is List && rows.isNotEmpty) {
      final parts = rows.first['metadataParts'];
      if (parts is List && parts.isNotEmpty) ch = _text(parts.first['text']);
    }
    var len = 0;
    final overlays = lk['contentImage']?['thumbnailViewModel']?['overlays'];
    if (overlays is List) {
      for (final o in overlays) {
        final badges = o['thumbnailOverlayBadgeViewModel']?['thumbnailBadges'];
        if (badges is List && badges.isNotEmpty) len = _parseLen('${badges.first['thumbnailBadgeViewModel']?['text'] ?? ''}');
      }
    }
    return title.isEmpty ? null : _make(id, title, ch, len);
  }

  // ---------------- Search ----------------

  @override
  Future<List<Track>> search(String query) async {
    final res = await _yt.search.search(query);
    return [for (final v in res) _toTrack(v)];
  }

  Track _toTrack(yt.Video v) {
    final t = _make(v.id.value, v.title, v.author, v.duration?.inMilliseconds ?? 0, art: v.thumbnails.highResUrl);
    return t.copyWith(extra: {'channel': v.author, 'views': v.engagement.viewCount});
  }

  Track _make(String id, String rawTitle, String channel, int ms, {String? art}) {
    var title = rawTitle;
    var artist = channel.replaceAll(RegExp(r'\s*-\s*Topic$'), '').replaceAll(RegExp(r'VEVO$'), '');
    final dash = title.indexOf(' - ');
    if (dash > 0) {
      artist = title.substring(0, dash).trim();
      title = title.substring(dash + 3).trim();
    }
    title = title.replaceAll(RegExp(r'\s*[\(\[](official|music|lyric|audio|video|visualizer)[^\)\]]*[\)\]]', caseSensitive: false), '').trim();
    return Track(
      id: '${SourceIds.youtube}:$id',
      uri: 'https://www.youtube.com/watch?v=$id',
      source: SourceIds.youtube,
      remoteId: id,
      title: title.isEmpty ? rawTitle : title,
      artist: artist,
      album: 'YouTube',
      durationMs: ms,
      artUri: art ?? 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
      isVideo: true,
      download: DownloadCapability.allowed,
      extra: {'channel': channel},
    );
  }

  // ---------------- Streams ----------------

  final _cache = <String, (yt.StreamManifest, String, DateTime)>{};

  /// Returns a manifest plus the User-Agent its URLs must be fetched with.
  Future<(yt.StreamManifest, String)> _manifest(String videoId) async {
    final c = _cache[videoId];
    if (c != null && DateTime.now().difference(c.$3) < const Duration(hours: 4)) return (c.$1, c.$2);
    final errors = <String>[];
    for (final (name, client, ua) in _clients) {
      try {
        final m = await _yt.videos.streams.getManifest(videoId, ytClients: [client]);
        if (m.audioOnly.isEmpty && m.muxed.isEmpty && m.hls.isEmpty) throw Exception('empty manifest');
        final probe = m.audioOnly.isNotEmpty ? m.audioOnly.first.url : (m.muxed.isNotEmpty ? m.muxed.first.url : m.hls.first.url);
        if (!await _probe(probe, ua)) throw Exception('stream URL rejected');
        Diag.info('yt.manifest', '$videoId via $name');
        _cache[videoId] = (m, ua, DateTime.now());
        return (m, ua);
      } catch (e) {
        errors.add('$name: ${e.toString().split('\n').first}');
      }
    }
    Diag.error('yt.manifest', 'All clients failed for $videoId', details: errors.join(' | '));
    throw Exception('YouTube stream unavailable (${errors.length} clients tried)');
  }

  static Future<bool> _probe(Uri url, String ua) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(url);
      req.headers.set(HttpHeaders.userAgentHeader, ua);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain<void>();
      return res.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  yt.AudioOnlyStreamInfo _bestAudio(yt.StreamManifest m) {
    final audio = m.audioOnly.toList();
    // AAC/m4a decodes everywhere on iOS; fall back to whatever exists.
    final mp4 = audio.where((s) => s.container == yt.StreamContainer.mp4).toList();
    final pick = (mp4.isNotEmpty ? mp4 : audio)..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return settings.dataSaver ? pick.last : pick.first;
  }

  @override
  Future<StreamInfo> resolveStream(Track track, {bool video = false}) async {
    final (m, ua) = await _manifest(track.remoteId!);
    final headers = {'User-Agent': ua};
    final exp = DateTime.now().add(const Duration(hours: 4));
    if (video) {
      if (m.hls.isNotEmpty) {
        final h = m.hls.toList()..sort((a, b) => b.bitrate.compareTo(a.bitrate));
        return StreamInfo(h.first.url.toString(), headers: headers, isVideo: true, expiresAt: exp);
      }
      if (m.muxed.isNotEmpty) {
        return StreamInfo(m.muxed.withHighestBitrate().url.toString(), headers: headers, isVideo: true, expiresAt: exp, mime: 'video/mp4');
      }
    }
    if (m.audioOnly.isEmpty) {
      if (m.muxed.isNotEmpty) return StreamInfo(m.muxed.withHighestBitrate().url.toString(), headers: headers, expiresAt: exp);
      throw Exception('No audio stream');
    }
    final s = _bestAudio(m);
    return StreamInfo(s.url.toString(), headers: headers, expiresAt: exp, mime: s.container == yt.StreamContainer.mp4 ? 'audio/mp4' : 'audio/webm');
  }

  @override
  DownloadCapability downloadCapability(Track track) => DownloadCapability.allowed;

  /// Audio downloads are m4a (AAC); with "Download video" on, the muxed mp4.
  @override
  Future<StreamInfo?> resolveDownload(Track track) async {
    final (m, ua) = await _manifest(track.remoteId!);
    final headers = {'User-Agent': ua, 'x-nok-chunked': '1'};
    if (settings.youtubeDownloadVideo && m.muxed.isNotEmpty) {
      return StreamInfo(m.muxed.withHighestBitrate().url.toString(), headers: headers, isVideo: true, mime: 'video/mp4');
    }
    final mp4 = m.audioOnly.where((s) => s.container == yt.StreamContainer.mp4).toList()..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    final s = mp4.isNotEmpty ? mp4.first : _bestAudio(m);
    return StreamInfo(s.url.toString(), headers: headers, mime: s.container == yt.StreamContainer.mp4 ? 'audio/mp4' : 'audio/webm');
  }
}
