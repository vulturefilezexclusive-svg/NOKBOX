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

  /// Fires when mpv rejected the active audio filter chain *while playing*.
  /// The backend has already cleared the filters so sound comes back; the
  /// equalizer uses this to stop re-applying a chain this build cannot run.
  Stream<void> get filterFailureStream;

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

  /// Applies a raw mpv-style audio filter chain; '' disables.
  ///
  /// Returns the chain mpv reports back after the set (`null` when the
  /// backend cannot be queried). mpv silently drops a filter chain it cannot
  /// build — and with it all audio — so callers must verify this result
  /// instead of assuming the chain took effect.
  Future<String?> setAudioFilter(String af);

  /// Chain mpv currently holds ('' when none).
  Future<String?> getAudioFilter();

  /// Reads an mpv property for diagnostics (e.g. 'ao', 'audio-device').
  Future<String?> getOption(String name);
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
  final _filterFailed = StreamController<void>.broadcast();
  final List<String> opened = [];
  final List<bool> openedAsVideo = [];
  String lastFilter = '';

  /// Filter names this fake "mpv build" was not built with. A chain that
  /// mentions one is rejected, exactly like the real iOS libmpv.
  final Set<String> unsupportedFilters = {};
  double volume = 100;
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = Duration.zero;
  final Set<String> failUrls = {};

  void complete() => _done.add(null);

  /// Simulates mpv failing to build the active chain during playback.
  void failFilter() {
    lastFilter = '';
    _filterFailed.add(null);
  }

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
  Stream<void> get filterFailureStream => _filterFailed.stream;

  @override
  Future<void> open(StreamInfo s, {Duration? start, bool play = true}) async {
    if (failUrls.contains(s.url)) throw Exception('stream failed: ${s.url}');
    opened.add(s.url);
    openedAsVideo.add(s.isVideo);
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
  Future<String?> setAudioFilter(String af) async {
    for (final f in unsupportedFilters) {
      if (af.contains(f)) return lastFilter = ''; // mpv keeps an empty chain
    }
    return lastFilter = af;
  }

  @override
  Future<String?> getAudioFilter() async => lastFilter;
  @override
  Future<String?> getOption(String name) async => null;
  @override
  Future<void> setOption(String name, String value) async {}
  @override
  Future<void> dispose() async {}
}
