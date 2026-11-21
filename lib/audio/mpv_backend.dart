import 'dart:async';

import 'package:media_kit/media_kit.dart';

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
    ]);
    _init();
  }

  late final Player player;
  final _subs = <StreamSubscription<dynamic>>[];
  final _completed = StreamController<void>.broadcast();
  final _advanced = StreamController<void>.broadcast();
  final _errors = StreamController<String>.broadcast();

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
    await player.open(Playlist([_media(s, start: start)]), play: play);
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
  Future<void> setSpeed(double s) => player.setRate(s);
  @override
  Future<void> setPitch(double p) => player.setPitch(p);

  @override
  Future<void> setAudioFilter(String af) async {
    await _native?.setProperty('af', af);
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
