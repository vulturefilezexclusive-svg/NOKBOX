import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Typed, persisted application settings.
///
/// Everything is stored as a single JSON blob so backups can export/import it
/// verbatim (see `BackupService`).
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs, this._values);

  static const _key = 'nokbox.settings.v1';
  final SharedPreferences? _prefs;
  final Map<String, dynamic> _values;

  static Future<SettingsStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    Map<String, dynamic> values = {};
    if (raw != null) {
      try {
        values = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    return SettingsStore._(prefs, values);
  }

  /// In-memory store for tests.
  factory SettingsStore.memory([Map<String, dynamic>? initial]) =>
      SettingsStore._(null, {...?initial});

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(_values);

  Future<void> importJson(Map<String, dynamic> json, {bool merge = true}) async {
    if (!merge) _values.clear();
    _values.addAll(json);
    await _persist();
    notifyListeners();
  }

  T get<T>(String key, T fallback) {
    final v = _values[key];
    if (v is T) return v;
    if (T == double && v is num) return v.toDouble() as T;
    if (T == int && v is num) return v.toInt() as T;
    if (v is List && fallback is List<String>) {
      return v.map((e) => e.toString()).toList() as T;
    }
    return fallback;
  }

  Future<void> set(String key, Object? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _prefs?.setString(_key, jsonEncode(_values));
  }

  // ---- Sources ----
  /// Free-text source field. Empty => YouTube (default feed).
  String get sourceField => get('sourceField', '');
  set sourceField(String v) => set('sourceField', v.trim());
  bool get autoSourceSwitch => get('autoSourceSwitch', true);
  set autoSourceSwitch(bool v) => set('autoSourceSwitch', v);
  String get podcastIndexKey => get('podcastIndexKey', '');
  String get podcastIndexSecret => get('podcastIndexSecret', '');
  bool get youtubeDownloadVideo => get('ytDownloadVideo', false);
  bool get dataSaver => get('dataSaver', false);

  // ---- Playback ----
  bool get gapless => get('gapless', true);
  String get replayGain => get('replayGain', 'track'); // no|track|album
  double get speed => get('speed', 1.0);
  double get pitch => get('pitch', 1.0);
  double get volume => get('volume', 100.0);
  bool get fadeOnPause => get('fadeOnPause', true);
  int get fadeMs => get('fadeMs', 250);
  double get loudnessBoostDb => get('loudnessBoostDb', 0.0);
  bool get resumeTracks => get('resumeTracks', true);
  int get resumeMinMinutes => get('resumeMinMinutes', 10);
  int get minListenSecondsForHistory => get('minListenSec', 20);
  bool get skipSilence => get('skipSilence', false);

  // ---- Library ----
  List<String> get libraryFolders => get<List<String>>('libraryFolders', <String>[]);
  List<String> get excludedFolders => get<List<String>>('excludedFolders', <String>[]);
  List<String> get watchFolders => get<List<String>>('watchFolders', <String>[]);
  int get minDurationSec => get('minDurationSec', 30);
  int get minSizeKb => get('minSizeKb', 100);
  bool get filterDuplicates => get('filterDuplicates', true);
  List<String> get artistSeparators =>
      get<List<String>>('artistSeparators', <String>[',', ' & ', ' x ', ';', ' / ']);
  List<String> get genreSeparators => get<List<String>>('genreSeparators', <String>[',', ';', '/']);
  bool get extractFeat => get('extractFeat', true);
  bool get includeVideos => get('includeVideos', true);

  // ---- UI ----
  bool get simpleMode => get('simpleMode', false);

  /// The mini player bar above the tab bar can be slid away; the choice is
  /// remembered so it stays out of the way until the user brings it back.
  bool get miniPlayerHidden => get('miniPlayerHidden', false);
  set miniPlayerHidden(bool v) => set('miniPlayerHidden', v);
  bool get waveformSeekbar => get('waveformSeekbar', true);
  bool get showVolumeOnPlayer => get('showVolumeOnPlayer', true);
  bool get batterySaver => get('batterySaver', false);
  bool get animatedArtwork => get('animatedArtwork', true);
  String get librarySort => get('librarySort', 'title');
  bool get librarySortDesc => get('librarySortDesc', false);
  bool get gridAlbums => get('gridAlbums', true);

  // ---- Lyrics ----
  bool get lyricsAutoFetch => get('lyricsAutoFetch', true);
  bool get lyricsSaveLrc => get('lyricsSaveLrc', false);
  double get lyricsFontScale => get('lyricsFontScale', 1.0);

  /// Heavy effects (animations, art blur, visual waveform) are disabled when
  /// battery saver is on.
  bool get heavyEffects => !batterySaver;
}
