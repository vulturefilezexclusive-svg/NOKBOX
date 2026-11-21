import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum DiagLevel { info, warn, error }

/// Background diagnostics.
///
/// Everything from launch is kept in an in-memory ring buffer that is
/// mirrored to a session temp file. Nothing is kept long-term unless
/// something goes wrong: the first error/exception/failed playback/failed
/// request "flags" the session, and the buffer (plus everything after it)
/// is written to a permanent report. A clean session's buffer is deleted on
/// clean exit and again on the next launch.
class Diag {
  Diag._();
  static const _max = 2000;
  static final _ring = <String>[];
  static Directory? _dir;
  static IOSink? _session;
  static File? _sessionFile;
  static File? _report;
  static bool flagged = false;
  static final changes = ValueNotifier<int>(0);
  static String appInfo = '';

  static Future<void> init(String supportDir, {String info = ''}) async {
    appInfo = info;
    _dir = Directory(p.join(supportDir, 'diagnostics'))..createSync(recursive: true);
    // Previous session ended without a flag → its buffer is just cache.
    for (final f in _dir!.listSync().whereType<File>()) {
      if (f.path.endsWith('.session')) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    _sessionFile = File(p.join(_dir!.path, 'current.session'));
    _session = _sessionFile!.openWrite();
    Diag.info('app', 'launch $info · ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  }

  static String _stamp() => DateTime.now().toIso8601String();

  static void _add(DiagLevel l, String tag, String msg, {String? details}) {
    final line = '${_stamp()} [${l.name.toUpperCase()}] $tag: $msg${details != null ? '\n    $details' : ''}';
    _ring.add(line);
    if (_ring.length > _max) _ring.removeRange(0, _ring.length - _max);
    _session?.writeln(line);
    if (kDebugMode) debugPrint(line);
    if (l == DiagLevel.error) _flag();
    if (flagged) _report?.writeAsStringSync('$line\n', mode: FileMode.append);
    changes.value++;
  }

  static void info(String tag, String msg) => _add(DiagLevel.info, tag, msg);
  static void warn(String tag, String msg) => _add(DiagLevel.warn, tag, msg);
  static void error(String tag, String msg, {Object? error, StackTrace? stack, String? details}) {
    final extra = [?details, if (error != null) '$error', if (stack != null) '$stack'].join('\n    ');
    _add(DiagLevel.error, tag, msg, details: extra.isEmpty ? null : extra);
  }

  static void _flag() {
    if (flagged || _dir == null) return;
    flagged = true;
    final name = 'report-${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.txt';
    _report = File(p.join(_dir!.path, name));
    _report!.writeAsStringSync('NOKBOX diagnostic report\n$appInfo\n${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n\n${_ring.join('\n')}\n');
  }

  static List<File> reports() {
    if (_dir == null) return const [];
    return _dir!.listSync().whereType<File>().where((f) => f.path.endsWith('.txt')).toList()..sort((a, b) => b.path.compareTo(a.path));
  }

  /// One file bundling all saved reports + the live buffer, for sharing.
  static Future<File> exportBundle() async {
    final out = File(p.join(_dir!.path, 'nokbox-diagnostics.log'));
    final b = StringBuffer('NOKBOX diagnostics export ${_stamp()}\n$appInfo\n\n');
    for (final r in reports()) {
      b.writeln('===== ${p.basename(r.path)} =====');
      b.writeln(await r.readAsString());
    }
    b.writeln('===== live session (last ${_ring.length} events) =====');
    b.writeln(_ring.join('\n'));
    await out.writeAsString(b.toString());
    return out;
  }

  static Future<void> clear() async {
    for (final r in reports()) {
      try {
        r.deleteSync();
      } catch (_) {}
    }
    _ring.clear();
    flagged = false;
    _report = null;
    changes.value++;
  }

  /// Clean exit: drop the cache buffer when nothing went wrong.
  static Future<void> cleanExit() async {
    await _session?.flush();
    await _session?.close();
    _session = null;
    if (!flagged) {
      try {
        _sessionFile?.deleteSync();
      } catch (_) {}
    }
  }

  /// Wire global error hooks.
  static void installHooks() {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      error('flutter', d.exceptionAsString(), stack: d.stack);
      prev?.call(d);
    };
    PlatformDispatcher.instance.onError = (e, s) {
      error('uncaught', '$e', stack: s);
      return true;
    };
  }
}
