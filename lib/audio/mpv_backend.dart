import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../core/diagnostics.dart';
import 'audio_backend.dart';

/// Production backend on top of media_kit (libmpv). Chosen because libmpv
/// runs one audio filter graph for every input — local files, HTTP(S)
/// progressive streams and HLS — on iOS, macOS, Linux, Windows and Android,
/// which is what lets the NOKBOX equalizer apply to streams as well as
/// local music. (AVPlayer-based engines cannot EQ remote streams without
/// MTAudioProcessingTap hacks; see HANDOFF.md.)
class MpvAudioBackend implements AudioBackend {
  MpvAudioBackend() {
    player = Player(configuration: const PlayerConfiguration(title: 'NOKBOX', pitch: true, bufferSize: 32 * 1024 * 1024));
    _subs.addAll([
      player.stream.completed.listen((c) {
        if (c && player.state.playlist.medias.length <= 1) _completed.add(null);
      }),
      player.stream.playlist.listen((pl) {
        // Gapless: when mpv moved to the pre-queued item (index 1), drop the
        // finished one and notify the controller.
        if (pl.index == 1 && pl.medias.length >= 2) {
          player.remove(0);
          _advanced.add(null);
        }
      }),
      player.stream.error.listen(_errors.add),
      player.stream.log.listen(_onLog),
    ]);
    _init();
  }

  late final Player player;
  final _subs = <StreamSubscription<dynamic>>[];
  final _completed = StreamController<void>.broadcast();
  final _advanced = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _filterFailed = StreamController<void>.broadcast();
  final _logged = <String>{};
  bool _recovering = false;

  /// Equalizer/FX chain requested by [EqualizerController] ('' = none).
  String _eqChain = '';

  /// Last rate/pitch asked for, so the equalizer and speed control can share
  /// one `af` chain (media_kit implements rate/pitch by overwriting it).
  double _rate = 1.0;
  double _pitch = 1.0;
  bool _pipelineLogged = false;

  NativePlayer? get _native => player.platform is NativePlayer ? player.platform as NativePlayer : null;

  Future<void> _init() async {
    await setOption('gapless-audio', 'weak');
    await setOption('prefetch-playlist', 'yes');
    await setOption('audio-pitch-correction', 'yes');
    await setOption('cache', 'yes');
    await setOption('demuxer-max-bytes', '64MiB');
    await setOption('ytdl', 'no'); // never shell out to youtube-dl/yt-dlp
    await setOption('volume-max', '150');
  }

  /// mpv reports audio-output and audio-filter failures on its log stream.
  /// Those are the lines that explain a device with no sound, so keep them in
  /// the diagnostics report (deduplicated; the buffer is a ring).
  void _onLog(PlayerLog e) {
    if (e.level != 'error' && e.level != 'fatal') return;
    const interesting = {'ao', 'af', 'ad', 'cplayer'};
    if (!interesting.contains(e.prefix)) return;
    final line = '${e.prefix}: ${e.text}';
    if (!_logged.add(line)) return;
    if (_logged.length > 40) _logged.remove(_logged.first);
    if (e.level == 'fatal') {
      Diag.error('mpv', line);
    } else {
      Diag.warn('mpv', line);
    }
    final lower = e.text.toLowerCase();
    if (lower.contains('filter') && (lower.contains('fail') || lower.contains('did not work') || lower.contains('error'))) {
      unawaited(_recoverFromFilterFailure(line));
    }
  }

  /// mpv validates the `af` property immediately but only *builds* the chain
  /// when a file's audio starts. A chain can therefore be accepted and still
  /// fail later, which silences the track. Clear the filters right away: mpv
  /// re-initialises them live, so the sound comes back and the equalizer is
  /// told to stop using a chain this build cannot run.
  Future<void> _recoverFromFilterFailure(String line) async {
    if (_eqChain.isEmpty || _recovering) return;
    _recovering = true;
    Diag.error('audio', 'audio filter chain failed during playback ($line) — clearing filters to restore sound');
    _eqChain = '';
    await _applyChain();
    _recovering = false;
    if (!_filterFailed.isClosed) _filterFailed.add(null);
  }

  /// The one `af` value that satisfies both the equalizer and media_kit's
  /// rate/pitch support.
  String get _composedChain {
    final parts = <String>[];
    if ((_rate - 1.0).abs() > 1e-6 || (_pitch - 1.0).abs() > 1e-6) {
      parts.add('scaletempo:scale=${(_rate / _pitch).toStringAsFixed(8)}');
    }
    if (_eqChain.isNotEmpty) parts.add(_eqChain);
    return parts.join(',');
  }

  /// Pushes [_composedChain] and returns what mpv built. An empty string means
  /// the chain was rejected (mpv keeps an empty filter chain, i.e. no audio),
  /// which is exactly what the equalizer must never let happen silently.
  Future<String?> _applyChain() async {
    final native = _native;
    if (native == null) return null;
    final chain = _composedChain;
    try {
      await native.setProperty('af', chain);
      final applied = (await native.getProperty('af')).trim();
      if (chain.isEmpty) return '';
      // mpv answers with the chain it holds; nothing means it was rejected.
      if (applied.isEmpty) return '';
      return applied;
    } catch (e) {
      Diag.warn('audio', 'audio filter chain rejected: $e');
      return '';
    }
  }

  Future<void> _logPipeline() async {
    final ao = await getOption('ao');
    final af = await getAudioFilter();
    final volume = player.state.volume;
    final hasChain = af != null && af.isNotEmpty;
    if (!_pipelineLogged) {
      _pipelineLogged = true;
      Diag.info('audio', 'pipeline: ao=${ao ?? '?'} volume=${volume.toStringAsFixed(1)} af=${hasChain ? af : 'none'}');
    } else {
      Diag.info('audio', 'pipeline: ao=${ao ?? '?'} volume=${volume.toStringAsFixed(1)}');
    }
    if (_eqChain.isNotEmpty && !hasChain) {
      Diag.warn('audio', 'equalizer chain not active — mpv would play without audio filters');
    }
  }

  @override
  Stream<bool> get playingStream => player.stream.playing;
  @override
  Stream<Duration> get positionStream => player.stream.position;
  @override
  Stream<Duration> get durationStream => player.stream.duration;
  @override
  Stream<bool> get bufferingStream => player.stream.buffering;
  @override
  Stream<void> get completedStream => _completed.stream;
  @override
  Stream<String> get errorStream => _errors.stream;
  @override
  Stream<void> get advancedToNextStream => _advanced.stream;
  @override
  Stream<void> get filterFailureStream => _filterFailed.stream;

  @override
  bool get playing => player.state.playing;
  @override
  Duration get position => player.state.position;
  @override
  Duration get duration => player.state.duration;

  Media _media(StreamInfo s, {Duration? start}) => Media(s.url, httpHeaders: s.headers, start: start);

  @override
  Future<void> open(StreamInfo s, {Duration? start, bool play = true}) async {
    // mpv's own requests (stream open, seeks) use the `user-agent` option,
    // not the per-media HTTP headers — so set it per track. Sources without
    // a UA get mpv's default back, so a YouTube client UA never leaks into
    // podcast / radio / archive requests (or local files, which need none).
    await setOption('user-agent', s.headers['User-Agent'] ?? 'libmpv');
    await setOption('vid', s.isVideo ? 'auto' : 'no');
    await player.open(Playlist([_media(s, start: start)]), play: play);
    await _logPipeline();
  }

  @override
  Future<void> preloadNext(StreamInfo? s) async {
    final medias = player.state.playlist.medias;
    if (medias.length > 1) {
      for (var i = medias.length - 1; i >= 1; i--) {
        await player.remove(i);
      }
    }
    if (s != null) await player.add(_media(s));
  }

  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> seek(Duration d) => player.seek(d);
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> setVolume(double percent) => player.setVolume(percent.clamp(0, 150));

  @override
  Future<void> setSpeed(double s) async {
    _rate = s;
    await player.setRate(s);
    await _applyChain();
  }

  @override
  Future<void> setPitch(double p) async {
    _pitch = p;
    await player.setPitch(p);
    await _applyChain();
  }

  @override
  Future<String?> setAudioFilter(String af) async {
    _eqChain = af;
    return _applyChain();
  }

  @override
  Future<String?> getAudioFilter() async {
    try {
      return (await _native?.getProperty('af'))?.trim();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getOption(String name) async {
    try {
      return await _native?.getProperty(name);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setOption(String name, String value) async {
    try {
      await _native?.setProperty(name, value);
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await player.dispose();
  }
}
