import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../app_globals.dart';
import '../../audio/mpv_backend.dart';
import '../../audio/playback_controller.dart';
import '../../audio/queue.dart';
import '../../core/settings.dart';
import '../../data/models.dart';
import '../../library/library_controller.dart';
import '../settings/equalizer_screen.dart';
import '../widgets/common.dart';
import 'lyrics_view.dart';
import 'player_sheets.dart';
import 'queue_screen.dart';
import 'seekbar.dart';
import '../../sources/youtube/sponsorblock.dart';
import 'youtube_extras.dart';

/// Full-screen player with gestures:
///  * swipe art left/right → next/previous
///  * double-tap left/right half → seek -10s/+10s
///  * swipe down → close; swipe up → queue
class FullPlayer extends StatefulWidget {
  const FullPlayer({super.key});

  static Route<void> route() => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => const FullPlayer(),
        transitionsBuilder: (_, a, _, child) => SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<FullPlayer> {
  bool _showLyrics = false;
  double _dragY = 0;
  VideoController? _video;

  VideoController? get video {
    final be = nok.backend;
    if (be is MpvAudioBackend) _video ??= VideoController(be.player);
    return _video;
  }

  @override
  Widget build(BuildContext context) {
    final pc = context.watch<PlaybackController>();
    final settings = context.watch<SettingsStore>();
    final lib = context.watch<LibraryController>();
    final t = pc.current;
    final cs = Theme.of(context).colorScheme;
    if (t == null) {
      return Scaffold(body: Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Nothing playing'))));
    }
    final showVideo = pc.videoMode && t.isVideo;
    final sponsor = context.watch<SponsorBlockController>();
    return GestureDetector(
      onVerticalDragUpdate: (d) => setState(() => _dragY = (_dragY + d.delta.dy).clamp(0, 400)),
      onVerticalDragEnd: (d) {
        if (_dragY > 120 || (d.primaryVelocity ?? 0) > 700) {
          Navigator.pop(context);
        } else if ((d.primaryVelocity ?? 0) < -700) {
          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const QueueScreen()));
        }
        setState(() => _dragY = 0);
      },
      child: Transform.translate(
        offset: Offset(0, _dragY),
        child: Scaffold(
          body: Stack(children: [
            if (settings.heavyEffects && t.artUri != null)
              Positioned.fill(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: Opacity(opacity: 0.35, child: Artwork(uri: t.artUri, radius: 0)),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [
                    cs.primary.withValues(alpha: 0.18),
                    cs.surface.withValues(alpha: 0.85),
                    cs.surface,
                  ]),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(children: [
                  _TopBar(queueName: pc.queue.name, track: t),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _showLyrics
                        ? const LyricsView()
                        : Center(
                            child: showVideo && video != null
                                ? AspectRatio(aspectRatio: 16 / 9, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Video(controller: video!, controls: AdaptiveVideoControls)))
                                : _ArtGestures(track: t, pc: pc),
                          ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Row(children: [
                          if (!t.isLocal) ...[SourceBadge(source: t.source), const SizedBox(width: 6)],
                          Expanded(child: Text(t.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: cs.onSurface.withValues(alpha: 0.75), fontWeight: FontWeight.w600))),
                        ]),
                      ]),
                    ),
                    IconButton(
                      iconSize: 28,
                      icon: Icon(lib.isFavorite(t.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: cs.primary),
                      onPressed: () => lib.toggleFavorite(t),
                    ),
                  ]),
                  if (t.source == SourceIds.youtube) YoutubeVotesRow(videoId: t.remoteId ?? ''),
                  const SizedBox(height: 10),
                  NokSeekBar(
                    position: pc.position,
                    duration: pc.duration,
                    onSeek: pc.seek,
                    waveform: settings.waveformSeekbar && settings.heavyEffects,
                    seed: t.id,
                    markers: sponsor.markers,
                  ),
                  const SizedBox(height: 6),
                  _Transport(pc: pc),
                  if (settings.showVolumeOnPlayer) _VolumeRow(pc: pc, settings: settings),
                  const SizedBox(height: 4),
                  _ActionRow(
                    showLyrics: _showLyrics,
                    onLyrics: () => setState(() => _showLyrics = !_showLyrics),
                    pc: pc,
                    track: t,
                  ),
                  const SizedBox(height: 8),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.queueName, required this.track});
  final String queueName;
  final Track track;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32), onPressed: () => Navigator.pop(context)),
      Expanded(
        child: Column(children: [
          Text('PLAYING FROM', style: TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w800, color: cs.onSurface.withValues(alpha: 0.6))),
          Text(queueName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
      IconButton(icon: const Icon(Icons.more_horiz_rounded), onPressed: () => showTrackActions(context, track)),
    ]);
  }
}

class _ArtGestures extends StatefulWidget {
  const _ArtGestures({required this.track, required this.pc});
  final Track track;
  final PlaybackController pc;
  @override
  State<_ArtGestures> createState() => _ArtGesturesState();
}

class _ArtGesturesState extends State<_ArtGestures> {
  double _dx = 0;
  String? _flash;

  void _seek(bool forward) {
    widget.pc.seekRelative(Duration(seconds: forward ? 10 : -10));
    setState(() => _flash = forward ? '+10s' : '-10s');
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest.shortestSide.clamp(120.0, 420.0);
      return GestureDetector(
        onHorizontalDragUpdate: (d) => setState(() => _dx += d.delta.dx),
        onHorizontalDragEnd: (d) {
          if (_dx < -80) widget.pc.next();
          if (_dx > 80) widget.pc.previous();
          setState(() => _dx = 0);
        },
        onDoubleTapDown: (d) => _seek(d.localPosition.dx > size / 2),
        onDoubleTap: () {},
        child: Stack(alignment: Alignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.translationValues(_dx * 0.6, 0, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: -6)],
            ),
            child: AnimatedScale(
              scale: widget.pc.playing ? 1 : 0.9,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              child: Hero(tag: 'art', child: Artwork(uri: widget.track.artUri, size: size, radius: 22, seed: widget.track.album, icon: widget.track.isVideo ? Icons.movie_rounded : null)),
            ),
          ),
          if (_flash != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(30)),
              child: Text(_flash!, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ),
        ]),
      );
    });
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.pc});
  final PlaybackController pc;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final repeatIcon = switch (pc.repeat) {
      RepeatMode.off => Icons.repeat_rounded,
      RepeatMode.all => Icons.repeat_on_rounded,
      RepeatMode.one => Icons.repeat_one_on_rounded,
    };
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      IconButton(icon: Icon(pc.shuffle ? Icons.shuffle_on_rounded : Icons.shuffle_rounded, color: pc.shuffle ? cs.primary : null), onPressed: pc.toggleShuffle),
      IconButton(iconSize: 40, icon: const Icon(Icons.skip_previous_rounded), onPressed: pc.previous),
      GestureDetector(
        onTap: pc.togglePlay,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primary,
            boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.5), blurRadius: 24)],
          ),
          child: pc.buffering
              ? Padding(padding: const EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 3, color: cs.onPrimary))
              : Icon(pc.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 44, color: cs.onPrimary),
        ),
      ),
      IconButton(iconSize: 40, icon: const Icon(Icons.skip_next_rounded), onPressed: pc.next),
      IconButton(icon: Icon(repeatIcon, color: pc.repeat != RepeatMode.off ? cs.primary : null), onPressed: pc.cycleRepeat),
    ]);
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({required this.pc, required this.settings});
  final PlaybackController pc;
  final SettingsStore settings;
  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.volume_down_rounded, size: 20),
        Expanded(child: Slider(value: settings.volume.clamp(0, 100), max: 100, onChanged: pc.setVolume)),
        const Icon(Icons.volume_up_rounded, size: 20),
      ]);
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.showLyrics, required this.onLyrics, required this.pc, required this.track});
  final bool showLyrics;
  final VoidCallback onLyrics;
  final PlaybackController pc;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget btn(IconData i, String label, VoidCallback onTap, {bool active = false}) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                Icon(i, color: active ? cs.primary : null, size: 22),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: active ? cs.primary : cs.onSurface.withValues(alpha: 0.7))),
              ]),
            ),
          ),
        );
    final sleepOn = pc.sleepMode != SleepMode.off;
    return Row(children: [
      btn(Icons.lyrics_rounded, 'Lyrics', onLyrics, active: showLyrics),
      btn(Icons.queue_music_rounded, 'Queue', () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const QueueScreen()))),
      btn(Icons.equalizer_rounded, 'EQ', () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const EqualizerScreen())), active: nok.eq.enabled),
      btn(Icons.bedtime_rounded, sleepOn ? sleepLabel(pc) : 'Sleep', () => showSleepTimerSheet(context), active: sleepOn),
      btn(Icons.speed_rounded, '${nok.settings.speed.toStringAsFixed(2)}x', () => showSpeedSheet(context)),
      if (track.isVideo) btn(pc.videoMode ? Icons.music_note_rounded : Icons.ondemand_video_rounded, pc.videoMode ? 'Audio' : 'Video', pc.toggleVideoMode, active: pc.videoMode),
    ]);
  }
}
