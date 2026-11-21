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

  /// Walks any InnerTube JSON tree and collects video tracks
  /// (videoRenderer / compactVideoRenderer / gridVideoRenderer /
  /// lockupViewModel), deduped by video id. Shared by the home feed and
  /// search so there is only one InnerTube parser.
  List<Track> _walkInnertube(dynamic j) {
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
    return items;
  }

  Future<List<FeedSection>> _innertubeFeed(String browseId, String title) async {
    final j = await account.innertube('browse', {'browseId': browseId});
    final items = _walkInnertube(j);
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
    // InnerTube POST, not the youtube.com/results HTML scrape: YouTube now
    // redirect-loops the scrape (bot/abuse check) while the API keeps
    // answering. Results are parsed with the same walk as the home feed.
    // No fallback to the scrape — it is the broken path.
    try {
      final j = await account.innertube('search', {'query': query});
      return _walkInnertube(j);
    } catch (e) {
      Diag.warn('yt.search', 'InnerTube search failed for "$query": $e');
      return const [];
    }
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

  /// Cached manifest + the UA its URLs need + the first audio stream that
  /// passed a probe (the URL resolveStream/resolveDownload hand out) +
  /// fetch time.
  final _cache = <String, (yt.StreamManifest, String, yt.AudioOnlyStreamInfo?, DateTime)>{};

  /// Drop one video's cached manifest so the next resolve re-fetches it
  /// (used after an open failure — googlevideo URLs expire).
  void invalidateManifest(String videoId) => _cache.remove(videoId);

  /// Returns a manifest, the User-Agent its URLs must be fetched with, and
  /// the audio stream whose URL passed a probe (null when the manifest has
  /// no separate audio — the player then uses muxed/HLS instead).
  Future<(yt.StreamManifest, String, yt.AudioOnlyStreamInfo?)> _manifest(String videoId) async {
    final c = _cache[videoId];
    if (c != null && DateTime.now().difference(c.$4) < const Duration(hours: 4)) return (c.$1, c.$2, c.$3);
    final errors = <String>[];
    for (final (name, client, ua) in _clients) {
      try {
        final m = await _yt.videos.streams.getManifest(videoId, ytClients: [client]);
        if (m.audioOnly.isEmpty && m.muxed.isEmpty && m.hls.isEmpty) throw Exception('empty manifest');
        yt.AudioOnlyStreamInfo? verified;
        if (m.audioOnly.isNotEmpty) {
          // Probe the URL that will actually be played/downloaded (best
          // first), not a sibling: v0.2.0 probed audioOnly.first but played
          // and downloaded _bestAudio — a different, unvalidated URL that
          // googlevideo 403s.
          verified = await _verifyAudio(videoId, m, ua);
          // Every audio-only URL was rejected. Keep the manifest when a muxed
          // or HLS stream exists: those usually still answer, so the player
          // can fall back to them instead of refusing the track outright
          // (which is what made YouTube need two taps to start).
          if (verified == null && m.muxed.isEmpty && m.hls.isEmpty) {
            throw Exception('stream URL rejected');
          }
        } else {
          // No separate audio: the player uses muxed (or HLS) — probe that.
          final fallback = m.muxed.isNotEmpty ? m.muxed.withHighestBitrate().url : m.hls.first.url;
          final code = await _probe(fallback, ua);
          Diag.info('yt.probe', '$videoId muxed -> $code');
          if (code == 0 || code >= 400) throw Exception('stream URL rejected');
        }
        Diag.info('yt.manifest', '$videoId via $name');
        _cache[videoId] = (m, ua, verified, DateTime.now());
        return (m, ua, verified);
      } catch (e) {
        errors.add('$name: ${e.toString().split('\n').first}');
      }
    }
    Diag.error('yt.manifest', 'All clients failed for $videoId', details: errors.join(' | '));
    throw Exception('YouTube stream unavailable (${errors.length} clients tried)');
  }

  /// Range-probe a stream URL. Returns the HTTP status code (0 when the
  /// request itself failed); only 0 < code < 400 means "the real fetch
  /// will probably succeed". Mirrors the real request: same UA header and
  /// a 0-1023 byte range, like the download manager's head probe.
  static Future<int> _probe(Uri url, String ua) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(url);
      req.headers.set(HttpHeaders.userAgentHeader, ua);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain<void>();
      return res.statusCode;
    } catch (_) {
      return 0;
    } finally {
      client.close(force: true);
    }
  }

  /// Probes audio candidates in play order and returns the first stream
  /// whose URL answers (null when every candidate was rejected).
  Future<yt.AudioOnlyStreamInfo?> _verifyAudio(String videoId, yt.StreamManifest m, String ua) async {
    for (final s in _audioCandidates(m)) {
      final code = await _probe(s.url, ua);
      Diag.info('yt.probe', '$videoId itag=${s.tag} -> $code');
      if (code > 0 && code < 400) return s;
    }
    return null;
  }

  /// Audio streams in the order they would be played/downloaded: the
  /// `_bestAudio` pick first, then the rest by bitrate desc.
  List<yt.AudioOnlyStreamInfo> _audioCandidates(yt.StreamManifest m) {
    final best = _bestAudio(m);
    final rest = m.audioOnly.where((s) => !identical(s, best)).toList()..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return [best, ...rest];
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
    final (m, ua, verified) = await _manifest(track.remoteId!);
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
    if (m.audioOnly.isEmpty || verified == null) {
      // Nothing audio-only answered: play the muxed/HLS stream (audio only —
      // the player keeps mpv's vid=no) rather than failing the track.
      if (m.muxed.isNotEmpty) {
        return StreamInfo(m.muxed.withHighestBitrate().url.toString(), headers: headers, expiresAt: exp, mime: 'video/mp4');
      }
      if (m.hls.isNotEmpty) return StreamInfo(m.hls.first.url.toString(), headers: headers, isVideo: true, expiresAt: exp);
      throw Exception('No playable stream');
    }
    // Play the stream whose URL passed its probe — never an unvalidated
    // sibling of it.
    final s = verified;
    return StreamInfo(s.url.toString(), headers: headers, expiresAt: exp, mime: s.container == yt.StreamContainer.mp4 ? 'audio/mp4' : 'audio/webm');
  }

  @override
  DownloadCapability downloadCapability(Track track) => DownloadCapability.allowed;

  /// Audio downloads are m4a (AAC); with "Download video" on, the muxed mp4.
  @override
  Future<StreamInfo?> resolveDownload(Track track) async {
    final (m, ua, verified) = await _manifest(track.remoteId!);
    final headers = {'User-Agent': ua, 'x-nok-chunked': '1'};
    if (settings.youtubeDownloadVideo && m.muxed.isNotEmpty) {
      return StreamInfo(m.muxed.withHighestBitrate().url.toString(), headers: headers, isVideo: true, mime: 'video/mp4');
    }
    if (m.audioOnly.isEmpty || verified == null) {
      // No verified audio URL: download the muxed stream (a playable file)
      // instead of guessing an unvalidated googlevideo URL that 403s and
      // leaves a broken file in the library.
      if (m.muxed.isNotEmpty) return StreamInfo(m.muxed.withHighestBitrate().url.toString(), headers: headers, mime: 'video/mp4');
      throw Exception('No downloadable stream');
    }
    // Download the probed candidate, not an unvalidated sibling:
    // v0.2.0's download 403d because the manifest only probed audioOnly.first.
    final s = verified;
    return StreamInfo(s.url.toString(), headers: headers, mime: s.container == yt.StreamContainer.mp4 ? 'audio/mp4' : 'audio/webm');
  }
}
