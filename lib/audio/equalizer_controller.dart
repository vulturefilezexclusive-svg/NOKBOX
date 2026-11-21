import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import 'audio_backend.dart';
import 'autoeq.dart';
import 'eq.dart';
import 'mpv_filters.dart';

/// State + persistence for the equalizer. Pushes the filter chain to the
/// active [AudioBackend] whenever it changes (same chain for local files
/// and streams). Supports per-output profiles (speaker/headphones/car).
class EqualizerController extends ChangeNotifier {
  EqualizerController({required this.db, required this.backend, this.builder = const MpvEqBuilder()}) {
    _load();
  }

  final NokDatabase db;
  AudioBackend backend;
  final MpvEqBuilder builder;

  bool enabled = true;
  bool autoPreamp = true;
  bool batterySaverBypass = false;
  EqProfile profile = EqProfile.builtIns[1];
  List<EqProfile> custom = [];

  /// output name -> profile name (e.g. "AirPods Pro" -> "AutoEQ AirPods Pro").
  Map<String, String> outputProfiles = {};
  String currentOutput = 'Speaker';

  /// Volume multiplier the playback controller applies for preamp.
  double get preampVolumeFactor => enabled && !batterySaverBypass ? MpvEqBuilder.preampToVolumeFactor(effectivePreamp) : 1.0;

  double get effectivePreamp {
    if (!autoPreamp) return profile.preampDb;
    final peak = profile.copyWith(preampDb: 0).estimatedPeakGain();
    return profile.preampDb < -peak ? profile.preampDb : -peak;
  }

  List<EqProfile> get allProfiles => [...EqProfile.builtIns, ...custom];

  void _load() {
    final raw = db.kvGet('eq.state');
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      enabled = j['enabled'] as bool? ?? true;
      autoPreamp = j['autoPreamp'] as bool? ?? true;
      custom = [for (final c in (j['custom'] as List? ?? const [])) EqProfile.fromJson(Map<String, dynamic>.from(c as Map))];
      if (j['profile'] != null) profile = EqProfile.fromJson(Map<String, dynamic>.from(j['profile'] as Map));
      outputProfiles = Map<String, String>.from(j['outputs'] as Map? ?? const {});
    } catch (_) {}
  }

  void _save() {
    db.kvSet('eq.state', jsonEncode({
      'enabled': enabled,
      'autoPreamp': autoPreamp,
      'profile': profile.toJson(),
      'custom': [for (final c in custom) c.toJson()],
      'outputs': outputProfiles,
    }));
  }

  String get filterChain => builder.build(profile, enabled: enabled && !batterySaverBypass);

  Future<void> apply() async {
    await backend.setAudioFilter(filterChain);
  }

  void _changed() {
    _save();
    apply();
    notifyListeners();
  }

  void setEnabled(bool v) {
    enabled = v;
    _changed();
  }

  void setAutoPreamp(bool v) {
    autoPreamp = v;
    _changed();
  }

  void select(EqProfile p) {
    profile = p;
    outputProfiles[currentOutput] = p.name;
    _changed();
  }

  void setBandGain(int i, double g) {
    final bands = [...profile.bands];
    bands[i] = bands[i].copyWith(gainDb: g);
    profile = profile.copyWith(bands: bands, builtIn: false, name: profile.builtIn ? '${profile.name} (edited)' : profile.name);
    _changed();
  }

  void updateBand(int i, EqBand b) {
    final bands = [...profile.bands];
    bands[i] = b;
    profile = profile.copyWith(bands: bands, builtIn: false);
    _changed();
  }

  void addBand(EqBand b) {
    profile = profile.copyWith(bands: [...profile.bands, b]..sort((a, c) => a.freq.compareTo(c.freq)), builtIn: false);
    _changed();
  }

  void removeBand(int i) {
    final bands = [...profile.bands]..removeAt(i);
    profile = profile.copyWith(bands: bands, builtIn: false);
    _changed();
  }

  void setPreamp(double db) {
    profile = profile.copyWith(preampDb: db);
    _changed();
  }

  void setBassBoost(double db) {
    profile = profile.copyWith(bassBoostDb: db);
    _changed();
  }

  // ---- FX: each setter rebuilds the lavfi chain exactly like the EQ
  // setters do (via _changed -> apply -> backend.setAudioFilter), so the
  // FX take effect live without touching playback.
  void setReverbAmount(double v) {
    profile = profile.copyWith(reverbAmount: v.clamp(0, 1));
    _changed();
  }

  void setReverbRoom(double v) {
    profile = profile.copyWith(reverbRoom: v.clamp(0, 1));
    _changed();
  }

  void setReverbDamping(double v) {
    profile = profile.copyWith(reverbDamping: v.clamp(0, 1));
    _changed();
  }

  void setReverbWet(double v) {
    profile = profile.copyWith(reverbWet: v.clamp(0, 1));
    _changed();
  }

  void setStereoWidth(double v) {
    profile = profile.copyWith(stereoWidth: v.clamp(0, 2));
    _changed();
  }

  void setVirtualizer(double v) {
    profile = profile.copyWith(virtualizer: v.clamp(0, 1));
    _changed();
  }

  void setThreeD(double v) {
    profile = profile.copyWith(threeD: v.clamp(0, 1));
    _changed();
  }

  void resetFx() {
    profile = profile.copyWith(reverbAmount: 0, reverbRoom: 0.5, reverbDamping: 0.5, reverbWet: 0.5, stereoWidth: 1, virtualizer: 0, threeD: 0);
    _changed();
  }

  void reset() => select(EqProfile.flat);

  void saveAs(String name) {
    final p = profile.copyWith(name: name, builtIn: false);
    custom.removeWhere((c) => c.name == name);
    custom.add(p);
    profile = p;
    _changed();
  }

  void deleteCustom(String name) {
    custom.removeWhere((c) => c.name == name);
    _changed();
  }

  EqProfile importAutoEq(String text, {required String name, String? attribution}) {
    final p = AutoEqParser.parse(text, name: name, attribution: attribution);
    custom.removeWhere((c) => c.name == p.name);
    custom.add(p);
    profile = p;
    _changed();
    return p;
  }

  EqProfile importJson(String json) {
    final p = EqProfile.fromJson(jsonDecode(json) as Map<String, dynamic>);
    custom.removeWhere((c) => c.name == p.name);
    custom.add(p);
    profile = p;
    _changed();
    return p;
  }

  /// Called when the audio route changes; switches to the saved profile.
  void onOutputChanged(String output) {
    currentOutput = output;
    final name = outputProfiles[output];
    if (name != null) {
      final p = allProfiles.where((e) => e.name == name).firstOrNull;
      if (p != null) {
        profile = p;
        _changed();
        return;
      }
    }
    notifyListeners();
  }

  void setBatterySaver(bool on) {
    batterySaverBypass = false; // EQ is cheap; only visual effects are cut.
    notifyListeners();
  }

  Map<String, dynamic> exportJson() => jsonDecode(db.kvGet('eq.state') ?? '{}') as Map<String, dynamic>;
}
