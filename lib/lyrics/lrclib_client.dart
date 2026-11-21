import 'dart:convert';

import 'package:http/http.dart' as http;

import '../sources/source_provider.dart';

class LrclibResult {
  LrclibResult({this.synced, this.plain, this.instrumental = false, this.id});
  final String? synced;
  final String? plain;
  final bool instrumental;
  final int? id;
}

/// LRCLIB (https://lrclib.net) — free, open, no key. Requests identify the
/// app via User-Agent as LRCLIB asks. Lookup with /api/get, fall back to
/// /api/search.
class LrclibClient {
  LrclibClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  static const _host = 'lrclib.net';

  Map<String, String> get _headers => {'User-Agent': nokUserAgent, 'Lrclib-Client': nokUserAgent};

  Future<LrclibResult?> get({required String title, required String artist, String album = '', int durationSec = 0}) async {
    final q = {'track_name': title, 'artist_name': artist, if (album.isNotEmpty) 'album_name': album, if (durationSec > 0) 'duration': '$durationSec'};
    final r = await _http.get(Uri.https(_host, '/api/get', q), headers: _headers);
    if (r.statusCode == 200) return _parse(jsonDecode(r.body) as Map);
    return search(title: title, artist: artist, durationSec: durationSec);
  }

  Future<LrclibResult?> search({required String title, required String artist, int durationSec = 0}) async {
    final r = await _http.get(Uri.https(_host, '/api/search', {'track_name': title, 'artist_name': artist}), headers: _headers);
    if (r.statusCode != 200) return null;
    final list = (jsonDecode(r.body) as List).cast<Map>();
    if (list.isEmpty) return null;
    list.sort((a, b) {
      int score(Map m) {
        final d = ((m['duration'] as num?) ?? 0).toInt();
        var s = durationSec > 0 ? (d - durationSec).abs() : 0;
        if (m['syncedLyrics'] == null) s += 30;
        return s;
      }

      return score(a).compareTo(score(b));
    });
    return _parse(list.first);
  }

  LrclibResult _parse(Map j) => LrclibResult(
        id: (j['id'] as num?)?.toInt(),
        synced: j['syncedLyrics'] as String?,
        plain: j['plainLyrics'] as String?,
        instrumental: j['instrumental'] == true,
      );
}
