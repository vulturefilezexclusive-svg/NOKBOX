import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Optional YouTube sign-in. Cookies captured from the in-app Google login
/// are kept in the iOS Keychain and only ever sent to youtube.com.
class YoutubeAccount extends ChangeNotifier {
  static const _store = FlutterSecureStorage();
  static const _key = 'yt_cookies_v1';
  static const origin = 'https://www.youtube.com';

  String _cookies = '';
  String? name;
  String? avatar;

  bool get signedIn => _cookies.contains('SAPISID=') || _cookies.contains('__Secure-3PAPISID=');
  String get cookieHeader => _cookies;

  Future<void> load() async {
    try {
      final raw = await _store.read(key: _key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _cookies = j['c'] as String? ?? '';
        name = j['n'] as String?;
        avatar = j['a'] as String?;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> save(String cookies, {String? displayName, String? avatarUrl}) async {
    _cookies = cookies;
    name = displayName ?? name;
    avatar = avatarUrl ?? avatar;
    try {
      await _store.write(key: _key, value: jsonEncode({'c': _cookies, 'n': name, 'a': avatar}));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> signOut() async {
    _cookies = '';
    name = null;
    avatar = null;
    try {
      await _store.delete(key: _key);
    } catch (_) {}
    notifyListeners();
  }

  String? _cookie(String n) {
    for (final part in _cookies.split(';')) {
      final i = part.indexOf('=');
      if (i > 0 && part.substring(0, i).trim() == n) return part.substring(i + 1).trim();
    }
    return null;
  }

  /// Headers for an authenticated InnerTube call (SAPISIDHASH scheme).
  Map<String, String> authHeaders() {
    if (!signedIn) return const {};
    final sapisid = _cookie('SAPISID') ?? _cookie('__Secure-3PAPISID') ?? '';
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hash = sha1.convert(utf8.encode('$ts $sapisid $origin')).toString();
    return {
      'Cookie': _cookies,
      'Authorization': 'SAPISIDHASH ${ts}_$hash',
      'X-Origin': origin,
      'Origin': origin,
      'X-Goog-AuthUser': '0',
    };
  }

  /// POST to an InnerTube endpoint with the WEB client (auth if signed in).
  Future<Map<String, dynamic>> innertube(String endpoint, Map<String, dynamic> body) async {
    final payload = {
      'context': {
        'client': {'clientName': 'WEB', 'clientVersion': '2.20251101.01.00', 'hl': 'en', 'gl': 'US'},
      },
      ...body,
    };
    final res = await http.post(
      Uri.parse('$origin/youtubei/v1/$endpoint?prettyPrint=false'),
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
        ...authHeaders(),
      },
      body: jsonEncode(payload),
    );
    if (res.statusCode != 200) throw Exception('YouTube $endpoint HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Fetch the signed-in account name/avatar (best effort).
  Future<void> refreshProfile() async {
    if (!signedIn) return;
    try {
      final j = await innertube('account/account_menu', {});
      final hdr = _find(j, 'activeAccountHeaderRenderer');
      if (hdr is Map) {
        name = (hdr['accountName']?['simpleText'] as String?) ?? name;
        final th = hdr['accountPhoto']?['thumbnails'];
        if (th is List && th.isNotEmpty) avatar = th.last['url'] as String?;
        await save(_cookies);
      }
    } catch (_) {}
  }

  static dynamic _find(dynamic node, String key) {
    if (node is Map) {
      if (node.containsKey(key)) return node[key];
      for (final v in node.values) {
        final r = _find(v, key);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _find(v, key);
        if (r != null) return r;
      }
    }
    return null;
  }
}
