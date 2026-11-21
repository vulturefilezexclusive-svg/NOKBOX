import 'dart:io';

import 'package:audio_service/audio_service.dart';

import '../data/models.dart';
import 'playback_controller.dart';
import 'queue.dart';

/// Bridges [PlaybackController] to the OS media session (lock screen,
/// Control Center, headphone buttons, Bluetooth) via audio_service.
class NokAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  NokAudioHandler(this.pc) {
    pc.addListener(_sync);
    _sync();
  }

  final PlaybackController pc;
  String? _lastId;
  int _lastQueueLen = -1;

  static MediaItem toItem(Track t) => MediaItem(
        id: t.id,
        title: t.title,
        artist: t.displayArtist,
        album: t.displayAlbum,
        duration: t.durationMs > 0 ? t.duration : null,
        artUri: t.artUri == null ? null : (t.artUri!.startsWith('http') ? Uri.parse(t.artUri!) : Uri.file(t.artUri!)),
        genre: t.genre,
      );

  void _sync() {
    final c = pc.current;
    if (c != null && (c.id != _lastId || mediaItem.value?.duration != pc.duration)) {
      _lastId = c.id;
      mediaItem.add(toItem(c).copyWith(duration: pc.duration > Duration.zero ? pc.duration : null));
    }
    if (pc.queue.items.length != _lastQueueLen) {
      _lastQueueLen = pc.queue.items.length;
      queue.add(pc.queue.items.map(toItem).toList());
    }
    playbackState.add(PlaybackState(
      controls: [MediaControl.skipToPrevious, pc.playing ? MediaControl.pause : MediaControl.play, MediaControl.skipToNext],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward, MediaAction.setShuffleMode, MediaAction.setRepeatMode},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: pc.current == null
          ? AudioProcessingState.idle
          : pc.buffering
              ? AudioProcessingState.buffering
              : AudioProcessingState.ready,
      playing: pc.playing,
      updatePosition: pc.position,
      speed: pc.settings.speed,
      queueIndex: pc.queue.index,
      repeatMode: switch (pc.repeat) {
        RepeatMode.off => AudioServiceRepeatMode.none,
        RepeatMode.all => AudioServiceRepeatMode.all,
        RepeatMode.one => AudioServiceRepeatMode.one,
      },
      shuffleMode: pc.shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    ));
  }

  @override
  Future<void> play() => pc.play();
  @override
  Future<void> pause() => pc.pause();
  @override
  Future<void> stop() => pc.pause();
  @override
  Future<void> seek(Duration position) => pc.seek(position);
  @override
  Future<void> skipToNext() => pc.next();
  @override
  Future<void> skipToPrevious() => pc.previous();
  @override
  Future<void> skipToQueueItem(int index) => pc.jumpTo(index);
  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async => pc.cycleRepeat();
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async => pc.toggleShuffle();
  @override
  Future<void> fastForward() => pc.seekRelative(const Duration(seconds: 10));
  @override
  Future<void> rewind() => pc.seekRelative(const Duration(seconds: -10));
}

Future<NokAudioHandler?> initAudioService(PlaybackController pc) async {
  if (!(Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) return null;
  try {
    return await AudioService.init(
      builder: () => NokAudioHandler(pc),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.nokbox.audio',
        androidNotificationChannelName: 'NOKBOX playback',
        androidNotificationOngoing: true,
      ),
    );
  } catch (_) {
    return null;
  }
}
