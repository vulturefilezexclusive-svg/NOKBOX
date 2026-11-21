import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nok_theme.dart';
import 'palette.dart';

/// Owns the active theme, user-saved themes and album-art dynamic accent.
class ThemeController extends ChangeNotifier {
  ThemeController._(this._prefs, this._spec, this._saved);

  static const _kActive = 'nokbox.theme.active';
  static const _kSaved = 'nokbox.theme.saved';
  final SharedPreferences? _prefs;
  NokThemeSpec _spec;
  final List<NokThemeSpec> _saved;
  Color? _dynamicAccent;
  ThemeData? _cache;

  static Future<ThemeController> load() async {
    final p = await SharedPreferences.getInstance();
    NokThemeSpec spec = NokThemeSpec.stock;
    final raw = p.getString(_kActive);
    if (raw != null) {
      try {
        spec = NokThemeSpec.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    final saved = <NokThemeSpec>[];
    for (final s in p.getStringList(_kSaved) ?? const <String>[]) {
      try {
        saved.add(NokThemeSpec.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
    return ThemeController._(p, spec, saved);
  }

  factory ThemeController.memory() => ThemeController._(null, NokThemeSpec.stock, []);

  NokThemeSpec get spec => _spec;
  List<NokThemeSpec> get saved => List.unmodifiable(_saved);
  Color? get dynamicAccent => _dynamicAccent;
  Color get accent => (_spec.dynamicFromArt && _dynamicAccent != null) ? _dynamicAccent! : _spec.accent;

  ThemeData get theme => _cache ??= buildNokTheme(_spec, dynamicAccent: _dynamicAccent);

  void apply(NokThemeSpec spec) {
    _spec = spec;
    _cache = null;
    _prefs?.setString(_kActive, jsonEncode(spec.toJson()));
    notifyListeners();
  }

  void update(NokThemeSpec Function(NokThemeSpec s) f) => apply(f(_spec));

  void resetToStock() => apply(NokThemeSpec.stock);

  Future<void> saveCurrentAs(String name) async {
    final s = _spec.copyWith(name: name);
    _saved.removeWhere((e) => e.name == name);
    _saved.add(s);
    await _persistSaved();
    apply(s);
  }

  Future<void> deleteSaved(String name) async {
    _saved.removeWhere((e) => e.name == name);
    await _persistSaved();
    notifyListeners();
  }

  /// Imports a theme JSON string. Returns the imported spec or throws.
  Future<NokThemeSpec> importTheme(String json) async {
    final map = jsonDecode(json) as Map<String, dynamic>;
    if (map['format'] != null && map['format'] != 'nokbox-theme') {
      throw const FormatException('Not a NOKBOX theme file');
    }
    final s = NokThemeSpec.fromJson(map);
    _saved.removeWhere((e) => e.name == s.name);
    _saved.add(s);
    await _persistSaved();
    apply(s);
    return s;
  }

  String exportTheme() => _spec.encode();

  Future<void> _persistSaved() async {
    await _prefs?.setStringList(_kSaved, _saved.map((e) => jsonEncode(e.toJson())).toList());
  }

  /// Called by the player when artwork changes.
  Future<void> updateFromArtwork(ImageProvider? image) async {
    if (!_spec.dynamicFromArt) return;
    final c = image == null ? null : await extractAccentColor(image);
    if (c == _dynamicAccent) return;
    _dynamicAccent = c;
    _cache = null;
    notifyListeners();
  }
}
