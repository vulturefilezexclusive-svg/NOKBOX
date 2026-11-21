import 'package:flutter/foundation.dart';

import '../audio/audio_backend.dart';
import '../core/settings.dart';
import '../data/models.dart';
import '../library/text_utils.dart';
import 'providers/archive_provider.dart';
import 'providers/custom_provider.dart';
import 'providers/podcast_provider.dart';
import 'providers/radio_provider.dart';
import 'providers/youtube_provider.dart';
import 'source_provider.dart';
import 'youtube/youtube_account.dart';

/// Holds every provider and maps the free-text Settings "Source" field to
/// the feed provider. Empty field => YouTube.
class SourceRegistry extends ChangeNotifier {
  SourceRegistry(this.settings, {List<SourceProvider>? providers, YoutubeAccount? account, List<Track> Function()? recentHistory}) {
    final list = providers ??
        [
          YoutubeProvider(settings, account ?? YoutubeAccount(), recentHistory: recentHistory),
          PodcastProvider(settings),
          RadioProvider(),
          ArchiveProvider(),
        ];
    for (final p in list) {
      _byId[p.id] = p;
    }
    settings.addListener(_onSettings);
    _lastField = settings.sourceField;
  }

  final SettingsStore settings;
  final Map<String, SourceProvider> _byId = {};
  final Map<String, CustomUrlProvider> _custom = {};
  String _lastField = '';

  List<SourceProvider> get builtIns => _byId.values.toList();
  SourceProvider? byId(String id) => _byId[id];

  void _onSettings() {
    if (settings.sourceField != _lastField) {
      _lastField = settings.sourceField;
      notifyListeners();
    }
  }

  /// Services we never integrate natively (DRM / ToS / circumvention).
  static const blocked = <String, String>{
    'gdstudio': 'This site re-serves paywalled/DRM streams without licences. NOKBOX will not integrate it.',
    'music.gdstudio.xyz': 'This site re-serves paywalled/DRM streams without licences. NOKBOX will not integrate it.',
  };

  /// Well-known services without a native provider open their own website
  /// (stream only).
  static const webHomes = <String, String>{
    'bandcamp': 'https://bandcamp.com/tag/hip-hop-rap',
    'spotify': 'https://open.spotify.com',
    'apple music': 'https://music.apple.com',
    'mixcloud': 'https://www.mixcloud.com',
    'hearthis': 'https://hearthis.at',
    'boomplay': 'https://www.boomplay.com',
    'anghami': 'https://play.anghami.com',
    'free music archive': 'https://freemusicarchive.org/genre/Hip-Hop',
    'fma': 'https://freemusicarchive.org/genre/Hip-Hop',
  };

  SourceProvider get feedProvider => resolveField(settings.sourceField);

  SourceProvider resolveField(String raw) {
    final field = raw.trim();
    if (field.isEmpty) return _byId[SourceIds.youtube]!;
    final lower = field.toLowerCase();
    for (final e in blocked.entries) {
      if (lower.contains(e.key)) return BlockedProvider(field, e.value);
    }
    final uri = Uri.tryParse(field.contains('://') ? field : (field.contains('.') && !field.contains(' ') ? 'https://$field' : ''));
    if (uri != null && uri.host.isNotEmpty) {
      return _custom.putIfAbsent(field, () => CustomUrlProvider(uri));
    }
    // Exact / alias match, then fuzzy.
    for (final p in _byId.values) {
      if (p.id == lower || p.name.toLowerCase() == lower || p.aliases.contains(lower)) return p;
    }
    SourceProvider? best;
    var bestScore = 0.0;
    for (final p in _byId.values) {
      for (final a in [p.name.toLowerCase(), ...p.aliases]) {
        final s = similarity(a, lower);
        if (s > bestScore) {
          bestScore = s;
          best = p;
        }
      }
    }
    if (best != null && bestScore >= 0.75) return best;
    final home = webHomes[lower] ?? 'https://www.${lower.replaceAll(' ', '')}.com';
    return WebSourceProvider(field, Uri.parse(home));
  }

  SourceProvider? providerFor(Track t) {
    if (t.source == SourceIds.custom) {
      // Match the provider the track came from. `_custom.values.firstOrNull`
      // returned whichever custom URL was typed first, so a second custom
      // source (and any download/capability question about it) was answered by
      // the wrong provider.
      final key = t.remoteId ?? t.uri;
      for (final p in _custom.values) {
        if (p.url.toString() == key) return p;
      }
      final uri = Uri.tryParse(key);
      return uri == null ? null : CustomUrlProvider(uri);
    }
    return _byId[t.source];
  }

  Future<StreamInfo> resolve(Track t, {bool video = false}) async {
    if (t.isLocal) return StreamInfo(t.uri, isVideo: t.isVideo);
    final p = providerFor(t);
    if (p == null) throw StateError('No provider for ${t.source}');
    return p.resolveStream(t, video: video);
  }

  DownloadCapability capability(Track t) {
    if (t.isLocal) return DownloadCapability.none;
    return providerFor(t)?.downloadCapability(t) ?? DownloadCapability.none;
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    super.dispose();
  }
}
