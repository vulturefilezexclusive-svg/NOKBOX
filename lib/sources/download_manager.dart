import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/diagnostics.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import 'source_provider.dart';
import 'source_registry.dart';

enum DownloadStatus { queued, running, done, failed, canceled }

class DownloadTask {
  DownloadTask(this.track);
  final Track track;
  DownloadStatus status = DownloadStatus.queued;
  double progress = 0;
  int received = 0;
  int total = 0;
  String? path;
  String? error;
  bool _cancel = false;
}

/// One download manager for every source. Only runs when the provider
/// declares [DownloadCapability.allowed]; `viaOfficialPage` opens the
/// service's own page; `none` is refused.
class DownloadManager extends ChangeNotifier {
  DownloadManager({required this.registry, required this.downloadsDir, required this.onFinished, http.Client? client})
      : _http = client ?? http.Client();

  final SourceRegistry registry;
  final String downloadsDir;
  final Future<void> Function() onFinished;
  final http.Client _http;
  final List<DownloadTask> tasks = [];
  int maxParallel = 2;

  int get active => tasks.where((t) => t.status == DownloadStatus.running).length;

  DownloadCapability capabilityOf(Track t) => registry.capability(t);

  /// Returns a user-facing message.
  Future<String> request(Track t) async {
    final cap = capabilityOf(t);
    switch (cap) {
      case DownloadCapability.none:
        return '${t.title}: this source is stream-only.';
      case DownloadCapability.viaOfficialPage:
        final page = registry.providerFor(t)?.officialPage(t);
        if (page != null) await launchUrl(page, mode: LaunchMode.externalApplication);
        return 'Opened the official page — downloads there land in Files › NOKBOX and get cataloged automatically.';
      case DownloadCapability.allowed:
        if (tasks.any((x) => x.track.id == t.id && x.status != DownloadStatus.failed && x.status != DownloadStatus.canceled)) {
          return 'Already in downloads.';
        }
        tasks.add(DownloadTask(t));
        notifyListeners();
        _pump();
        return 'Downloading ${t.title}';
    }
  }

  void cancel(DownloadTask t) {
    t._cancel = true;
    if (t.status == DownloadStatus.queued) t.status = DownloadStatus.canceled;
    notifyListeners();
  }

  void clearFinished() {
    tasks.removeWhere((t) => t.status == DownloadStatus.done || t.status == DownloadStatus.canceled || t.status == DownloadStatus.failed);
    notifyListeners();
  }

  void retry(DownloadTask t) {
    t.status = DownloadStatus.queued;
    t._cancel = false;
    t.error = null;
    t.received = 0;
    t.total = 0;
    t.progress = 0;
    notifyListeners();
    _pump();
  }

  void _pump() {
    while (active < maxParallel) {
      final next = tasks.where((t) => t.status == DownloadStatus.queued).firstOrNull;
      if (next == null) return;
      _run(next);
    }
  }

  static String safeName(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// itag from a googlevideo URL query (null for other sources).
  static String? _itagOf(String? url) {
    if (url == null) return null;
    return Uri.tryParse(url)?.queryParameters['itag'];
  }

  Future<void> _run(DownloadTask task) async {
    task.status = DownloadStatus.running;
    notifyListeners();
    IOSink? sink;
    File? tmp;
    String? infoUrl;
    int? lastStatus;
    try {
      final provider = registry.providerFor(task.track);
      final info = await provider?.resolveDownload(task.track);
      if (info == null) throw Exception('No permitted download for this track');
      infoUrl = info.url;
      final chunked = info.headers.containsKey('x-nok-chunked');
      final headers = {'User-Agent': nokUserAgent, ...info.headers}..remove('x-nok-chunked');
      // YouTube throttles/aborts single long requests, so fetch in ranges.
      Stream<List<int>> body;
      String ct;
      if (chunked) {
        const step = 9 * 1024 * 1024;
        final head = await _http.send(http.Request('GET', Uri.parse(info.url))..headers.addAll({...headers, 'Range': 'bytes=0-0'}));
        await head.stream.drain<void>();
        final headStatus = head.statusCode;
        lastStatus = headStatus;
        if (headStatus >= 400) throw Exception('HTTP $headStatus');
        final cr = head.headers['content-range'] ?? '';
        task.total = int.tryParse(cr.split('/').last) ?? 0;
        ct = info.mime ?? head.headers['content-type'] ?? '';
        var total = task.total;
        Stream<List<int>> ranges() async* {
          var start = 0;
          while (total == 0 || start < total) {
            final end = total == 0 ? start + step - 1 : (start + step - 1).clamp(0, total - 1);
            final r = await _http.send(http.Request('GET', Uri.parse(info.url))..headers.addAll({...headers, 'Range': 'bytes=$start-$end'}));
            final rangeStatus = r.statusCode;
            lastStatus = rangeStatus;
            if (rangeStatus >= 400) throw Exception('HTTP $rangeStatus');
            // 206 = the range was honoured. A 200 means the server ignored
            // `Range` and sent the whole body, so this response is the file:
            // continuing the loop would ask for the next range and either
            // duplicate the whole file or, with an unknown total, loop
            // forever on a download that never finishes.
            final partial = rangeStatus == 206;
            if (!partial && total == 0) {
              total = r.contentLength ?? 0;
              task.total = total;
            }
            var got = 0;
            await for (final c in r.stream) {
              got += c.length;
              yield c;
            }
            if (got == 0 || !partial) break;
            start += got;
          }
        }
        body = ranges();
      } else {
        final res = await _http.send(http.Request('GET', Uri.parse(info.url))..headers.addAll(headers));
        final getStatus = res.statusCode;
        lastStatus = getStatus;
        if (getStatus >= 400) throw Exception('HTTP $getStatus');
        task.total = res.contentLength ?? 0;
        ct = info.mime ?? res.headers['content-type'] ?? '';
        body = res.stream;
      }
      final ext = ct.startsWith('video/') ? '.mp4' : ct.contains('webm') ? '.webm' : ct.contains('mpeg') ? '.mp3' : ct.contains('mp4') || ct.contains('m4a') ? '.m4a' : ct.contains('ogg') ? '.ogg' : ct.contains('flac') ? '.flac' : '.mp3';
      final dir = Directory(p.join(downloadsDir, safeName(task.track.displayArtist)))..createSync(recursive: true);
      final finalPath = p.join(dir.path, '${safeName('${task.track.displayArtist} - ${task.track.title}')}$ext');
      tmp = File('$finalPath.part');
      sink = tmp.openWrite();
      await for (final chunk in body) {
        if (task._cancel) throw const _Canceled();
        sink.add(chunk);
        task.received += chunk.length;
        task.progress = task.total > 0 ? task.received / task.total : 0;
        notifyListeners();
      }
      await sink.close();
      sink = null;
      // A stream can end short without raising an error (dead range request,
      // dropped socket). Never promote that partial file to done: it would be
      // renamed into Documents and cataloged as a playable, broken track.
      if (task.total > 0 && task.received < task.total) {
        throw Exception('Incomplete download (${task.received}/${task.total} bytes)');
      }
      await tmp.rename(finalPath);
      task.path = finalPath;
      task.status = DownloadStatus.done;
      task.progress = 1;
      await onFinished();
    } on _Canceled {
      task.status = DownloadStatus.canceled;
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.error = '$e';
      // Pinpoint the dead stream: itag from the URL + the HTTP status, so
      // the next export shows which stream died instead of a bare 403.
      Diag.error('download', 'Failed: ${task.track.title}', error: e, details: 'itag=${_itagOf(infoUrl) ?? '?'} status=${lastStatus ?? '?'}');
    } finally {
      await sink?.close();
      if (task.status != DownloadStatus.done && tmp != null && tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
      notifyListeners();
      _pump();
    }
  }
}

class _Canceled implements Exception {
  const _Canceled();
}
