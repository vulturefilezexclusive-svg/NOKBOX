import 'package:material_ui/material_ui.dart';

import '../audio/audio_backend.dart';
import '../data/models.dart';

enum FeedLayout { carousel, list, grid, chips }

class FeedSection {
  const FeedSection({required this.title, required this.items, this.subtitle, this.layout = FeedLayout.carousel});
  final String title;
  final String? subtitle;
  final List<Track> items;
  final FeedLayout layout;
}

/// Thrown when a provider needs configuration (API key, approval...).
class ProviderSetupRequired implements Exception {
  ProviderSetupRequired(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Pluggable source. Every provider returns [Track]s into the same catalog
/// and plays through the same engine + EQ. Providers declare per-track
/// download permission; the download button only appears where allowed.
abstract class SourceProvider {
  String get id;
  String get name;
  String get tagline;
  IconData get icon;
  Color get brandColor;

  /// Names users might type into the Source field.
  List<String> get aliases => const [];

  /// Legal / licensing notes shown in Settings › Sources.
  String get licenseNote;

  /// Non-null when the provider can't work until the user configures it.
  String? get setupHint => null;

  /// Web-only fallback (renders the service's own site in a web view).
  Uri? get webUrl => null;

  Future<List<FeedSection>> browse();
  Future<List<Track>> search(String query);

  /// Expands a collection item (podcast show, archive item, playlist).
  Future<List<Track>> expand(Track collection) async => const [];
  bool isCollection(Track t) => t.extra['collection'] == true;

  Future<StreamInfo> resolveStream(Track track, {bool video = false});
  DownloadCapability downloadCapability(Track track);

  /// Direct download stream; only called when capability == allowed.
  Future<StreamInfo?> resolveDownload(Track track) async => resolveStream(track);

  /// Official page for `viaOfficialPage` downloads / "open in app".
  Uri? officialPage(Track track) => null;
}

const nokUserAgent = 'NOKBOX/0.1.0 (https://github.com/vulturefilezexclusive-svg/NOKBOX)';
