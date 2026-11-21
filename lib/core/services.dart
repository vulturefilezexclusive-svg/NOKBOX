import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../audio/audio_backend.dart';
import '../audio/audio_handler.dart';
import '../audio/equalizer_controller.dart';
import '../audio/mpv_backend.dart';
import '../audio/playback_controller.dart';
import '../backup/backup_service.dart';
import '../data/database.dart';
import '../library/library_controller.dart';
import '../lyrics/lyrics_controller.dart';
import '../sources/download_manager.dart';
import '../sources/source_matcher.dart';
import '../sources/source_registry.dart';
import '../sources/youtube/sponsorblock.dart';
import 'settings.dart';
import 'theme/theme_controller.dart';

/// Composition root.
class Services {
  Services._({
    required this.settings,
    required this.theme,
    required this.db,
    required this.library,
    required this.registry,
    required this.eq,
    required this.playback,
    required this.lyrics,
    required this.downloads,
    required this.backup,
    required this.backend,
    required this.sponsorBlock,
    required this.ryd,
  });

  final SettingsStore settings;
  final ThemeController theme;
  final NokDatabase db;
  final LibraryController library;
  final SourceRegistry registry;
  final EqualizerController eq;
  final PlaybackController playback;
  final LyricsController lyrics;
  final DownloadManager downloads;
  final BackupService backup;
  final AudioBackend backend;
  final SponsorBlockController sponsorBlock;
  final RydClient ryd;
  NokAudioHandler? handler;

  static Future<Services> init({AudioBackend? backend}) async {
    final settings = await SettingsStore.load();
    final theme = await ThemeController.load();
    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final dataDir = Directory(p.join(support.path, 'nokbox'))..createSync(recursive: true);
    final db = NokDatabase.open(p.join(dataDir.path, 'nokbox.db'));
    final musicDir = Platform.isIOS ? docs.path : p.join(docs.path, 'NOKBOX');
    Directory(musicDir).createSync(recursive: true);
    final downloadsDir = p.join(musicDir, 'NOKBOX Downloads');
    final library = LibraryController(db: db, settings: settings, documentsDir: musicDir, artDir: p.join(dataDir.path, 'art'));
    library.loadFromDb();
    final registry = SourceRegistry(settings);
    final be = backend ?? MpvAudioBackend();
    final eq = EqualizerController(db: db, backend: be);
    final matcher = SourceMatcher(localTracks: () => library.tracks, providers: () => registry.builtIns);
    final playback = PlaybackController(backend: be, registry: registry, db: db, settings: settings, eq: eq, matcher: matcher);
    eq.addListener(playback.refreshVolume);
    final lyrics = LyricsController(db: db, settings: settings);
    final downloads = DownloadManager(registry: registry, downloadsDir: downloadsDir, onFinished: () async => library.rescan());
    final backup = BackupService(db: db, settings: settings, theme: theme, eq: eq);
    final s = Services._(
      settings: settings,
      theme: theme,
      db: db,
      library: library,
      registry: registry,
      eq: eq,
      playback: playback,
      lyrics: lyrics,
      downloads: downloads,
      backup: backup,
      backend: be,
      sponsorBlock: SponsorBlockController(pc: playback, backend: be, settings: settings),
      ryd: RydClient(),
    );
    await playback.applyEngineSettings();
    s.handler = await initAudioService(playback);
    library.startWatching();
    library.rescan();
    return s;
  }
}
