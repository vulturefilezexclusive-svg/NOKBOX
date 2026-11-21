import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../../audio/audio_backend.dart';
import '../../audio/playback_controller.dart';
import '../../core/settings.dart';
import '../../data/models.dart';
import '../../ui/player/seekbar.dart';
import '../source_provider.dart';

enum SbAction { skip, mute, show, off }

class SbCategory {
  const SbCategory(this.id, this.label, this.color, this.defaultAction);
  final String id;
  final String label;
  final Color color;
  final SbAction defaultAction;
}

/// SponsorBlock categories (https://wiki.sponsor.ajay.app/w/Types).
const sbCategories = <SbCategory>[
  SbCategory('sponsor', 'Sponsor', Color(0xFF00D400), SbAction.skip),
  SbCategory('selfpromo', 'Self-promotion', Color(0xFFFFFF00), SbAction.skip),
  SbCategory('interaction', 'Interaction reminder (subscribe)', Color(0xFFCC00FF), SbAction.skip),
  SbCategory('music_offtopic', 'Non-music section (music videos)', Color(0xFFFF9900), SbAction.skip),
  SbCategory('intro', 'Intro / intermission', Color(0xFF00FFFF), SbAction.show),
  SbCategory('outro', 'Endcards / credits', Color(0xFF0202ED), SbAction.show),
  SbCategory('preview', 'Preview / recap', Color(0xFF008FD6), SbAction.show),
  SbCategory('filler', 'Filler tangent', Color(0xFF7300FF), SbAction.off),
];

class SbSegment {
  SbSegment(this.category, this.start, this.end, this.uuid, this.actionType);
  final String category;
  final Duration start;
  final Duration end;
  final String uuid;
  final String actionType;
}

/// SponsorBlock API client (https://sponsor.ajay.app, data CC BY-NC-SA 4.0).
/// Uses the privacy-preserving hash-prefix endpoint: only the first 4 hex
/// chars of sha256(videoId) leave the device.
class SponsorBlockClient {
  SponsorBlockClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static String hashPrefix(String videoId) => sha256.convert(utf8.encode(videoId)).toString().substring(0, 4);

  Future<List<SbSegment>> segments(String videoId, List<String> categories) async {
    if (categories.isEmpty) return const [];
    final uri = Uri.https('sponsor.ajay.app', '/api/skipSegments/${hashPrefix(videoId)}', {
      'categories': jsonEncode(categories),
      'actionTypes': jsonEncode(['skip', 'mute', 'full']),
    });
    final r = await _http.get(uri, headers: {'User-Agent': nokUserAgent});
    if (r.statusCode == 404) return const [];
    if (r.statusCode != 200) throw Exception('SponsorBlock ${r.statusCode}');
    return parse(r.body, videoId);
  }

  static List<SbSegment> parse(String body, String videoId) {
    final list = jsonDecode(body) as List;
    final out = <SbSegment>[];
    for (final v in list) {
      if (v['videoID'] != videoId) continue;
      for (final s in (v['segments'] as List)) {
        final seg = (s['segment'] as List).cast<num>();
        out.add(SbSegment(
          s['category'] as String,
          Duration(milliseconds: (seg[0] * 1000).round()),
          Duration(milliseconds: (seg[1] * 1000).round()),
          s['UUID'] as String? ?? '',
          s['actionType'] as String? ?? 'skip',
        ));
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }
}

/// Watches playback; auto-skips / mutes segments per user category settings
/// and exposes seek-bar markers.
class SponsorBlockController extends ChangeNotifier {
  SponsorBlockController({required this.pc, required this.backend, required this.settings, SponsorBlockClient? client})
      : _client = client ?? SponsorBlockClient() {
    pc.addListener(_tick);
  }

  final PlaybackController pc;
  final AudioBackend backend;
  final SettingsStore settings;
  final SponsorBlockClient _client;

  String? _videoId;
  List<SbSegment> segments = [];
  final Set<String> _handled = {};
  bool _muted = false;

  bool get enabled => settings.get('sb.enabled', true);
  SbAction actionFor(String cat) {
    final def = sbCategories.firstWhere((c) => c.id == cat, orElse: () => sbCategories.first).defaultAction;
    final v = settings.get('sb.$cat', def.name);
    return SbAction.values.firstWhere((a) => a.name == v, orElse: () => def);
  }

  Future<void> setAction(String cat, SbAction a) async {
    await settings.set('sb.$cat', a.name);
    _videoId = null; // refetch with new categories
    _tick();
  }

  List<SeekMarker> get markers => [
        for (final s in segments)
          SeekMarker(s.start, s.end, sbCategories.firstWhere((c) => c.id == s.category, orElse: () => sbCategories.first).color, label: s.category),
      ];

  void _tick() {
    final t = pc.current;
    final vid = (t != null && t.source == SourceIds.youtube && enabled) ? t.remoteId : null;
    if (vid != _videoId) {
      _videoId = vid;
      segments = [];
      _handled.clear();
      _unmute();
      notifyListeners();
      if (vid != null) _load(vid);
      return;
    }
    if (segments.isEmpty) return;
    final pos = pc.position;
    var inMute = false;
    for (final s in segments) {
      final inside = pos >= s.start && pos < s.end - const Duration(milliseconds: 300);
      if (!inside) continue;
      final a = actionFor(s.category);
      if (a == SbAction.skip && s.actionType != 'mute' && !_handled.contains(s.uuid)) {
        _handled.add(s.uuid);
        pc.seek(s.end);
        _toast('Skipped ${s.category.replaceAll('_', ' ')}');
      } else if (a == SbAction.mute || (a == SbAction.skip && s.actionType == 'mute')) {
        inMute = true;
      }
    }
    if (inMute && !_muted) {
      _muted = true;
      backend.setVolume(0);
    } else if (!inMute && _muted) {
      _unmute();
    }
  }

  void _unmute() {
    if (!_muted) return;
    _muted = false;
    pc.refreshVolume();
  }

  final _toasts = <String>[];
  String? takeToast() => _toasts.isEmpty ? null : _toasts.removeAt(0);
  void _toast(String m) {
    _toasts.add(m);
    notifyListeners();
  }

  Future<void> _load(String vid) async {
    final cats = [for (final c in sbCategories) if (actionFor(c.id) != SbAction.off) c.id];
    try {
      final s = await _client.segments(vid, cats);
      if (_videoId == vid) {
        segments = s.where((x) => actionFor(x.category) != SbAction.off).toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    pc.removeListener(_tick);
    super.dispose();
  }
}

/// Return YouTube Dislike (https://returnyoutubedislike.com) — community
/// estimated dislike counts. Read-only GET /votes?videoId=.
class RydVotes {
  RydVotes({required this.likes, required this.dislikes, required this.views, required this.rating});
  final int likes;
  final int dislikes;
  final int views;
  final double rating;
}

class RydClient {
  RydClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  final _cache = <String, RydVotes>{};

  Future<RydVotes?> votes(String videoId) async {
    if (videoId.isEmpty) return null;
    if (_cache[videoId] != null) return _cache[videoId];
    final r = await _http.get(Uri.https('returnyoutubedislikeapi.com', '/votes', {'videoId': videoId}), headers: {'User-Agent': nokUserAgent});
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map;
    return _cache[videoId] = RydVotes(
      likes: (j['likes'] as num? ?? 0).toInt(),
      dislikes: (j['dislikes'] as num? ?? 0).toInt(),
      views: (j['viewCount'] as num? ?? 0).toInt(),
      rating: (j['rating'] as num? ?? 0).toDouble(),
    );
  }
}
