import 'dart:async';
import '../core/diagnostics.dart';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/settings.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../sources/providers/youtube_provider.dart';
import '../sources/source_matcher.dart';
import '../sources/source_registry.dart';
import 'audio_backend.dart';
import 'equalizer_controller.dart';
import 'queue.dart';

enum SleepMode { off, minutes, tracks, endOfTrack }

/// Central playback brain: multiple live queues, gapless pre-loading,
/// auto source switching, resume points, history, sleep timer, fades.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this.backend,
    required this.registry,
    required this.db,
    required this.settings,
    required this.eq,
    required this.matcher,
  }) {
    _subs.addAll([
      backend.playingStream.listen((p) {
        _playing = p;
        notifyListeners();
      }),
      backend.positionStream.listen(_onPosition),
      backend.durationStream.listen((d) {
        _duration = d;
        notifyListeners();
      }),
      backend.bufferingStream.listen((b) {
        _buffering = b;
        notifyListeners();
      }),
      backend.completedStream.listen((_) => _onCompleted()),
      backend.advancedToNextStream.listen((_) => _onGaplessAdvance()),
      backend.errorStream.listen((e) => _onBackendError(e)),
    ]);
    final raw = db.kvGet('queues');
    if (raw != null) {
      try {
        queues = QueueSet.decode(raw);
      } catch (_) {}
    }
  }

  final AudioBackend backend;
  final SourceRegistry registry;
  final NokDatabase db;
  final SettingsStore settings;
  final EqualizerController eq;
  final SourceMatcher matcher;
  final _subs = <StreamSubscription<dynamic>>[];
  final _messages = StreamController<String>.broadcast();

  QueueSet queues = QueueSet();
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _loadToken = 0;
  bool _preloaded = false;
  Track? _preloadedTrack;
  int _listenedMs = 0;
  Duration _lastPos = Duration.zero;
  DateTime _lastResumeSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool videoMode = false;
  String? lastError;
  Track? switchedFrom;
  String? _failedTrack;
  DateTime _failedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _persistDebounce;

  /// YouTube video ids that already got their one fresh-manifest retry for
  /// the current play attempt. (The `tried` set can't guard this alone:
  /// mpv open failures arrive async via _onBackendError with a fresh set.)
  /// Cleared for a track when a fresh play attempt for it starts.
  final _ytRetried = <String>{};

  // Sleep timer
  SleepMode sleepMode = SleepMode.off;
  DateTime? sleepAt;
  int sleepTracksLeft = 0;
  Timer? _sleepTicker;

  Stream<String> get messages => _messages.stream;
  PlayQueue get queue => queues.current;
  Track? get current => queue.current;
  bool get playing => _playing;
  bool get buffering => _buffering;
  Duration get position => _position;
  Duration get duration => _duration > Duration.zero ? _duration : (current?.duration ?? Duration.zero);
  RepeatMode get repeat => queue.repeat;
  bool get shuffle => queue.shuffled;
  Duration? get sleepRemaining => sleepAt?.difference(DateTime.now());

  double get targetVolume {
    final boost = math.pow(10, settings.loudnessBoostDb / 60).toDouble();
    return (settings.volume * eq.preampVolumeFactor * boost).clamp(0, 150).toDouble();
  }

  // ---------------- queue entry points ----------------

  Future<void> playTracks(List<Track> tracks, {int start = 0, bool newQueue = false, String? queueName, bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    _commitListen();
    final q = newQueue ? queues.create(name: queueName) : queue;
    if (newQueue) queues.active = queues.queues.indexOf(q);
    q.items
      ..clear()
      ..addAll(tracks);
    q.index = start.clamp(0, tracks.length - 1);
    q.shuffled = false;
    if (shuffle) q.setShuffle(true);
    if (queueName != null) q.name = queueName;
    await _playIndex(q.index);
  }

  void playNext(List<Track> tracks) {
    if (queue.isEmpty) {
      playTracks(tracks);
      return;
    }
    queue.playNext(tracks);
    _invalidatePreload();
    _changed();
    _messages.add(tracks.length == 1 ? 'Playing next: ${tracks.first.title}' : '${tracks.length} tracks play next');
  }

  void addToQueue(List<Track> tracks) {
    if (queue.isEmpty) {
      playTracks(tracks);
      return;
    }
    queue.add(tracks);
    _invalidatePreload();
    _changed();
    _messages.add(tracks.length == 1 ? 'Added to queue: ${tracks.first.title}' : 'Added ${tracks.length} tracks to queue');
  }

  void removeAt(int i) {
    final wasCurrent = i == queue.index;
    queue.removeAt(i);
    _invalidatePreload();
    if (wasCurrent && current != null) _playIndex(queue.index);
    _changed();
  }

  void move(int from, int to) {
    queue.move(from, to);
    _invalidatePreload();
    _changed();
  }

  void clearQueue() {
    backend.stop();
    queue.items.clear();
    queue.index = 0;
    _changed();
  }

  // ---------------- multiple queues ----------------

  Future<void> switchQueue(int i) async {
    if (i == queues.active || i < 0 || i >= queues.queues.length) return;
    _commitListen();
    queue.positionMs = _position.inMilliseconds;
    queues.active = i;
    _changed();
    if (current != null) {
      await _playIndex(queue.index, start: Duration(milliseconds: queue.positionMs), autoplay: _playing);
    } else {
      await backend.stop();
    }
  }

  void newQueue({String? name, List<Track>? tracks}) {
    final q = queues.create(name: name);
    if (tracks != null) q.items.addAll(tracks);
    _changed();
  }

  void renameQueue(int i, String name) {
    queues.queues[i].name = name;
    _changed();
  }

  void deleteQueue(int i) {
    final wasActive = i == queues.active;
    queues.delete(i);
    if (wasActive) {
      backend.stop();
      if (current != null) _playIndex(queue.index, start: Duration(milliseconds: queue.positionMs), autoplay: false);
    }
    _changed();
  }

  // ---------------- transport ----------------

  Future<void> togglePlay() => _playing ? pause() : play();

  Future<void> play() async {
    if (current == null) return;
    if (backend.duration == Duration.zero && _position == Duration.zero && !_buffering) {
      await _playIndex(queue.index, start: Duration(milliseconds: queue.positionMs));
      return;
    }
    if (settings.fadeOnPause) {
      await backend.setVolume(0);
      await backend.play();
      await _ramp(0, targetVolume);
    } else {
      await backend.setVolume(targetVolume);
      await backend.play();
    }
  }

  Future<void> pause() async {
    if (settings.fadeOnPause && _playing) {
      await _ramp(targetVolume, 0);
      await backend.pause();
      await backend.setVolume(targetVolume);
    } else {
      await backend.pause();
    }
    _saveResume();
    _persist();
  }

  Future<void> _ramp(double from, double to) async {
    final ms = settings.fadeMs;
    if (ms <= 0) return;
    const steps = 10;
    for (var i = 1; i <= steps; i++) {
      await backend.setVolume(from + (to - from) * i / steps);
      await Future<void>.delayed(Duration(milliseconds: ms ~/ steps));
    }
  }

  Future<void> next() async {
    _commitListen();
    final n = queue.nextIndex(userInitiated: true);
    if (n == null) return;
    await _playIndex(n);
  }

  Future<void> previous() async {
    if (_position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    _commitListen();
    final p = queue.previousIndex();
    if (p == null) return;
    await _playIndex(p);
  }

  Future<void> jumpTo(int i) async {
    _commitListen();
    await _playIndex(i);
  }

  Future<void> seek(Duration d) async {
    await backend.seek(d);
    _position = d;
    _lastPos = d;
    notifyListeners();
  }

  Future<void> seekRelative(Duration delta) async {
    final t = _position + delta;
    await seek(t < Duration.zero ? Duration.zero : (t > duration ? duration : t));
  }

  void cycleRepeat() {
    queue.repeat = RepeatMode.values[(queue.repeat.index + 1) % RepeatMode.values.length];
    _invalidatePreload();
    _changed();
  }

  void toggleShuffle() {
    queue.setShuffle(!queue.shuffled);
    _invalidatePreload();
    _changed();
  }

  Future<void> setSpeed(double s) async {
    await settings.set('speed', s);
    await backend.setSpeed(s);
    notifyListeners();
  }

  Future<void> setPitch(double p) async {
    await settings.set('pitch', p);
    await backend.setPitch(p);
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    await settings.set('volume', v);
    await backend.setVolume(targetVolume);
    notifyListeners();
  }

  /// Re-applies volume after EQ preamp changes.
  Future<void> refreshVolume() => backend.setVolume(targetVolume);

  Future<void> applyEngineSettings() async {
    await backend.setOption('replaygain', settings.replayGain);
    await backend.setOption('replaygain-clip', 'no');
    await backend.setOption('gapless-audio', settings.gapless ? 'weak' : 'no');
    await backend.setSpeed(settings.speed);
    await backend.setPitch(settings.pitch);
    await backend.setVolume(targetVolume);
    await eq.apply();
  }

  Future<void> toggleVideoMode() async {
    videoMode = !videoMode;
    final c = current;
    if (c != null && !c.isLocal && c.isVideo) {
      await _playIndex(queue.index, start: _position, autoplay: _playing);
    }
    notifyListeners();
  }

  // ---------------- loading ----------------

  Future<void> _playIndex(int i, {Duration? start, bool autoplay = true, Set<String> tried = const {}}) async {
    if (i < 0 || i >= queue.items.length) return;
    final token = ++_loadToken;
    queue.index = i;
    final t = queue.items[i];
    // Fresh play attempt (not a retry): the track may earn its one
    // fresh-manifest retry again.
    if (tried.isEmpty) _ytRetried.remove(t.remoteId);
    lastError = null;
    _preloaded = false;
    _preloadedTrack = null;
    _position = start ?? Duration.zero;
    _lastPos = _position;
    _listenedMs = 0;
    _duration = t.duration;
    _buffering = true;
    _changed();
    try {
      final info = await registry.resolve(t, video: videoMode);
      if (token != _loadToken) return;
      var startAt = start;
      if (startAt == null && settings.resumeTracks && t.durationMs >= settings.resumeMinMinutes * 60000) {
        final saved = db.resumeFor(t.id);
        if (saved != null && saved < t.durationMs - 15000) startAt = Duration(milliseconds: saved);
      }
      await backend.setVolume(autoplay && settings.fadeOnPause ? 0 : targetVolume);
      await backend.open(info, start: startAt, play: autoplay);
      if (autoplay && settings.fadeOnPause) unawaited(_ramp(0, targetVolume));
      if (startAt != null) _position = startAt;
    } catch (e) {
      if (token != _loadToken) return;
      await _handleFailure(t, i, '$e', autoplay: autoplay, tried: {...tried, t.id});
    }
    notifyListeners();
  }

  Future<void> _handleFailure(Track t, int i, String error, {required bool autoplay, required Set<String> tried}) async {
    lastError = error;
    Diag.warn('playback', '${t.id} failed: $error');
    if (settings.autoSourceSwitch && tried.length < 4) {
      _messages.add('${t.title} failed on ${t.source} — searching other sources…');
      final alt = await matcher.findAlternative(t, exclude: tried);
      if (alt != null) {
        switchedFrom = t;
        queue.items[i] = alt;
        _messages.add('Switched to ${alt.source == SourceIds.local ? 'your library' : alt.source}');
        await _playIndex(i, autoplay: autoplay, tried: tried);
        return;
      }
    }
    // YouTube: the cached manifest may have gone stale (expired googlevideo
    // URL). Bust it and retry once with a fresh manifest before giving up.
    if (t.source == SourceIds.youtube && t.remoteId != null && !_ytRetried.contains(t.remoteId)) {
      final provider = registry.byId(SourceIds.youtube);
      if (provider is YoutubeProvider) {
        _ytRetried.add(t.remoteId!);
        provider.invalidateManifest(t.remoteId!);
        _messages.add('Retrying ${t.title} with a fresh stream…');
        await _playIndex(i, autoplay: autoplay, tried: {...tried, 'yt-retry:${t.remoteId}'});
        return;
      }
    }
    Diag.error('playback', 'Couldn\'t play ${t.title} (${t.source})', details: error);
    _messages.add('Couldn\'t play ${t.title}');
    _buffering = false;
    notifyListeners();
  }

  void _onBackendError(String e) {
    // Audio-pipeline failures are not stream failures: mpv keeps playing
    // (without sound) and the equalizer/backend repair the chain. Treating
    // these as fatal would switch sources in a loop and make the track look
    // like it never plays at all.
    final lower = e.toLowerCase();
    if (lower.contains('filter') || lower.contains('audio device') || lower.contains('audio output') || lower.contains('audio driver')) return;
    final t = current;
    if (t == null || _position > const Duration(seconds: 2)) return;
    // Error before playback really started -> try another source, but not
    // more than once every few seconds for the same track.
    final now = DateTime.now();
    if (_failedTrack == t.id && now.difference(_failedAt) < const Duration(seconds: 3)) return;
    _failedTrack = t.id;
    _failedAt = now;
    _handleFailure(t, queue.index, e, autoplay: true, tried: {t.id});
  }

  void _onPosition(Duration p) {
    final delta = p - _lastPos;
    if (delta > Duration.zero && delta < const Duration(seconds: 2)) _listenedMs += delta.inMilliseconds;
    _lastPos = p;
    _position = p;
    if (_buffering && _playing) _buffering = false;
    final d = duration;
    if (settings.gapless && !_preloaded && d > Duration.zero && d - p < const Duration(seconds: 12)) {
      _preloaded = true;
      _preloadNext();
    }
    if (DateTime.now().difference(_lastResumeSave) > const Duration(seconds: 5)) {
      _lastResumeSave = DateTime.now();
      _saveResume();
    }
    _tickSleepFade();
    notifyListeners();
  }

  Future<void> _preloadNext() async {
    final n = queue.nextIndex();
    if (n == null || n == queue.index) return;
    final t = queue.items[n];
    try {
      final info = await registry.resolve(t, video: videoMode);
      _preloadedTrack = t;
      await backend.preloadNext(info);
    } catch (_) {
      _preloadedTrack = null;
    }
  }

  void _invalidatePreload() {
    if (_preloadedTrack != null) backend.preloadNext(null);
    _preloaded = false;
    _preloadedTrack = null;
  }

  void _onGaplessAdvance() {
    final pre = _preloadedTrack;
    if (pre == null) return;
    _commitListen();
    db.clearResume(current?.id ?? '');
    final idx = queue.items.indexOf(pre);
    if (idx >= 0) queue.index = idx;
    _preloaded = false;
    _preloadedTrack = null;
    _position = Duration.zero;
    _lastPos = Duration.zero;
    _duration = pre.duration;
    _afterTrackFinished();
    _changed();
  }

  void _onCompleted() {
    _commitListen();
    final c = current;
    if (c != null) db.clearResume(c.id);
    if (_afterTrackFinished()) return;
    final n = queue.nextIndex();
    if (n == null) {
      _playing = false;
      notifyListeners();
      return;
    }
    _playIndex(n);
  }

  /// Returns true when the sleep timer stopped playback.
  bool _afterTrackFinished() {
    if (sleepMode == SleepMode.endOfTrack || (sleepMode == SleepMode.tracks && --sleepTracksLeft <= 0)) {
      cancelSleep();
      backend.pause();
      _messages.add('Sleep timer: goodnight 🌙');
      return true;
    }
    return false;
  }

  void _commitListen() {
    final c = current;
    if (c == null) return;
    if (_listenedMs >= settings.minListenSecondsForHistory * 1000 || (c.durationMs > 0 && _listenedMs > c.durationMs * 0.5)) {
      db.logPlay(c, _listenedMs);
    }
    _listenedMs = 0;
  }

  void _saveResume() {
    final c = current;
    if (c == null || !settings.resumeTracks) return;
    if (c.durationMs >= settings.resumeMinMinutes * 60000 && _position > const Duration(seconds: 30)) {
      db.saveResume(c.id, _position.inMilliseconds);
    }
    queue.positionMs = _position.inMilliseconds;
  }

  // ---------------- sleep timer ----------------

  void setSleepMinutes(int minutes) {
    cancelSleep();
    sleepMode = SleepMode.minutes;
    sleepAt = DateTime.now().add(Duration(minutes: minutes));
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (sleepAt != null && DateTime.now().isAfter(sleepAt!)) {
        cancelSleep();
        pause();
        _messages.add('Sleep timer: goodnight 🌙');
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void setSleepTracks(int n) {
    cancelSleep();
    sleepMode = SleepMode.tracks;
    sleepTracksLeft = n;
    notifyListeners();
  }

  void setSleepEndOfTrack() {
    cancelSleep();
    sleepMode = SleepMode.endOfTrack;
    notifyListeners();
  }

  void cancelSleep() {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    sleepMode = SleepMode.off;
    sleepAt = null;
    sleepTracksLeft = 0;
    backend.setVolume(targetVolume);
    notifyListeners();
  }

  /// Gentle fade over the final 30 s of a minutes-based sleep timer.
  void _tickSleepFade() {
    final r = sleepRemaining;
    if (sleepMode != SleepMode.minutes || r == null) return;
    if (r < const Duration(seconds: 30) && r > Duration.zero) {
      backend.setVolume(targetVolume * r.inMilliseconds / 30000);
    }
  }

  // ---------------- persistence ----------------

  void _changed() {
    notifyListeners();
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 800), _persist);
  }

  void _persist() {
    queue.positionMs = _position.inMilliseconds;
    db.kvSet('queues', queues.encode());
  }

  /// Saves the active queue as a playlist (session).
  int saveQueueAsPlaylist(String name) {
    final id = db.createPlaylist(name, description: 'Saved queue');
    db.addToPlaylist(id, queue.items);
    return id;
  }

  @override
  void dispose() {
    _persist();
    for (final s in _subs) {
      s.cancel();
    }
    _sleepTicker?.cancel();
    super.dispose();
  }
}
