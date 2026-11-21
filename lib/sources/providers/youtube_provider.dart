import 'package:material_ui/material_ui.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../audio/audio_backend.dart';
import '../../core/settings.dart';
import '../../data/models.dart';
import '../source_provider.dart';

/// Compile-time switch: the YouTube downloader is an optional add-on that is
/// OFF in default builds (and must stay off for any App Store build).
/// Enable with `--dart-define=NOKBOX_YT_DOWNLOADS=true`.
const kYoutubeDownloaderBuild = bool.fromEnvironment('NOKBOX_YT_DOWNLOADS');

class YoutubeProvider extends SourceProvider {
  YoutubeProvider(this.settings);
  final SettingsStore settings;
  final _yt = yt.YoutubeExplode();

  @override
  String get id => SourceIds.youtube;
  @override
  String get name => 'YouTube';
  @override
  String get tagline => 'Default feed · videos, music videos, freestyles';
  @override
  IconData get icon => Icons.smart_display_rounded;
  @override
  Color get brandColor => const Color(0xFFFF0000);
  @override
  List<String> get aliases => const ['youtube', 'yt', 'youtube music', 'ytm'];
  @override
  String get licenseNote =>
      'Streams public YouTube videos. Downloading is an optional add-on that is disabled in standard builds; respect YouTube\'s Terms of Service and creators\' rights.';
  @override
  Uri? officialPage(Track track) => Uri.parse('https://www.youtube.com/watch?v=${track.remoteId}');

  static const _shelves = <(String, String)>[
    ('Hip Hop Heat', 'new hip hop songs this week'),
    ('Trap Bangers', 'trap music new releases'),
    ('Drill Season', 'new drill music'),
    ('R&B Vibes', 'new r&b songs'),
    ('Freestyles & Cyphers', 'freestyle cypher 2026'),
    ('Underground Picks', 'underground rap new'),
  ];

  @override
  Future<List<FeedSection>> browse() async {
    final out = <FeedSection>[];
    for (final (title, q) in _shelves) {
      try {
        final items = await search(q);
        if (items.isNotEmpty) out.add(FeedSection(title: title, items: items.take(15).toList()));
      } catch (_) {}
      if (out.length >= 4) break;
    }
    return out;
  }

  @override
  Future<List<Track>> search(String query) async {
    final res = await _yt.search.search(query);
    return [for (final v in res) _toTrack(v)];
  }

  Track _toTrack(yt.Video v) {
    var title = v.title;
    var artist = v.author.replaceAll(RegExp(r'\s*-\s*Topic$'), '').replaceAll(RegExp(r'VEVO$'), '');
    final dash = title.indexOf(' - ');
    if (dash > 0) {
      artist = title.substring(0, dash).trim();
      title = title.substring(dash + 3).trim();
    }
    title = title.replaceAll(RegExp(r'\s*[\(\[](official|music|lyric|audio|video|visualizer)[^\)\]]*[\)\]]', caseSensitive: false), '').trim();
    return Track(
      id: '${SourceIds.youtube}:${v.id.value}',
      uri: v.url,
      source: SourceIds.youtube,
      remoteId: v.id.value,
      title: title,
      artist: artist,
      album: 'YouTube',
      durationMs: v.duration?.inMilliseconds ?? 0,
      artUri: v.thumbnails.highResUrl,
      isVideo: true,
      download: downloadCapability(Track(id: '', uri: '', title: '')),
      extra: {'channel': v.author, 'views': v.engagement.viewCount},
    );
  }

  @override
  Future<StreamInfo> resolveStream(Track track, {bool video = false}) async {
    final manifest = await _yt.videos.streams.getManifest(track.remoteId!, ytClients: [yt.YoutubeApiClient.safari, yt.YoutubeApiClient.androidVr]);
    if (video && manifest.muxed.isNotEmpty) {
      final s = manifest.muxed.withHighestBitrate();
      return StreamInfo(s.url.toString(), isVideo: true);
    }
    final audio = manifest.audioOnly;
    if (audio.isEmpty) throw Exception('No audio stream');
    // Prefer AAC/mp4 on iOS for broadest decoder support, else highest bitrate.
    final mp4 = audio.where((s) => s.container == yt.StreamContainer.mp4).toList();
    final pick = (mp4.isNotEmpty ? mp4 : audio.toList())..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    final s = settings.dataSaver ? pick.last : pick.first;
    return StreamInfo(s.url.toString(), expiresAt: DateTime.now().add(const Duration(hours: 5)));
  }

  @override
  DownloadCapability downloadCapability(Track track) =>
      (kYoutubeDownloaderBuild && settings.youtubeDownloaderEnabled) ? DownloadCapability.allowed : DownloadCapability.none;
}
