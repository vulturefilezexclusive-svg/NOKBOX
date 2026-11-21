import 'dart:async';

/// Resolved, playable stream for a track.
class StreamInfo {
  const StreamInfo(this.url, {this.headers = const {}, this.isVideo = false, this.expiresAt, this.mime});
  final String url;
  final Map<String, String> headers;
  final bool isVideo;
  final DateTime? expiresAt;
  final String? mime;
}

/// Minimal audio backend contract so playback logic is testable without a
/// native player. The production implementation is [MpvAudioBackend].
abstract class AudioBackend {
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get bufferingStream;
  Stream<void> get completedStream;
  Stream<String> get errorStream;

  /// Fires when the gapless pre-queued item became the active one.
  Stream<void> get advancedToNextStream;

  bool get playing;
  Duration get position;
  Duration get duration;

  Future<void> open(StreamInfo s, {Duration? start, bool play = true});

  /// Pre-buffer the next item for gapless transitions.
  Future<void> preloadNext(StreamInfo? s);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration d);
  Future<void> stop();
  Future<void> setVolume(double percent);
  Future<void> setSpeed(double s);
  Future<void> setPitch(double p);

  /// Raw mpv-style audio filter chain; '' disables.
  Future<void> setAudioFilter(String af);
  Future<void> setOption(String name, String value);
  Future<void> dispose();
}

/// In-memory fake used by unit tests.
class FakeAudioBackend implements AudioBackend {
  final _playing = StreamController<bool>.broadcast();
  final _pos = StreamController<Duration>.broadcast();
  final _dur = StreamController<Duration>.broadcast();
  final _buf = StreamController<bool>.broadcast();
  final _done = StreamController<void>.broadcast();
  final _err = StreamController<String>.broadcast();
  final _adv = StreamController<void>.broadcast();
  final List<String> opened = [];
  String lastFilter = '';
  double volume = 100;
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = Duration.zero;
  final Set<String> failUrls = {};

  void complete() => _done.add(null);

  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<Duration> get durationStream => _dur.stream;
  @override
  Stream<bool> get bufferingStream => _buf.stream;
  @override
  Stream<void> get completedStream => _done.stream;
  @override
  Stream<String> get errorStream => _err.stream;
  @override
  Stream<void> get advancedToNextStream => _adv.stream;

  @override
  Future<void> open(StreamInfo s, {Duration? start, bool play = true}) async {
    if (failUrls.contains(s.url)) throw Exception('stream failed: ${s.url}');
    opened.add(s.url);
    position = start ?? Duration.zero;
    playing = play;
    _playing.add(play);
  }

  @override
  Future<void> preloadNext(StreamInfo? s) async {}
  @override
  Future<void> play() async {
    playing = true;
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    playing = false;
    _playing.add(false);
  }

  @override
  Future<void> seek(Duration d) async {
    position = d;
    _pos.add(d);
  }

  @override
  Future<void> stop() async => pause();
  @override
  Future<void> setVolume(double percent) async => volume = percent;
  @override
  Future<void> setSpeed(double s) async {}
  @override
  Future<void> setPitch(double p) async {}
  @override
  Future<void> setAudioFilter(String af) async => lastFilter = af;
  @override
  Future<void> setOption(String name, String value) async {}
  @override
  Future<void> dispose() async {}
}
