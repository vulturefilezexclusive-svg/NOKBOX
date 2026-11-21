import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../audio/playback_controller.dart';
import '../root_shell.dart';
import '../settings/equalizer_screen.dart';
import '../widgets/common.dart';

/// Persistent mini player: tap to expand, swipe up to expand, swipe down to
/// slide the bar away, swipe left/right to skip, progress line on top.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, this.onHide});

  /// Called when the bar is swiped down or its chevron is tapped. The host
  /// remembers the choice, so the bar stays out of the way until it is asked
  /// for again.
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    final pc = context.watch<PlaybackController>();
    final t = pc.current;
    if (t == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final total = pc.duration.inMilliseconds;
    final frac = total > 0 ? (pc.position.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
    return GestureDetector(
      onTap: () => RootShell.openPlayer(context),
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200) {
          RootShell.openPlayer(context);
        } else if (v > 200) {
          onHide?.call();
        }
      },
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) pc.next();
        if (v > 300) pc.previous();
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        decoration: BoxDecoration(
          color: Color.alphaBlend(cs.primary.withValues(alpha: 0.10), cs.surfaceContainerHigh),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: frac, minHeight: 2.5, backgroundColor: Colors.transparent, color: cs.primary),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
            child: Row(children: [
              Hero(tag: 'art', child: Artwork(uri: t.artUri, size: 44, radius: 10, seed: t.album)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(
                    pc.buffering ? 'Loading…' : t.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.65)),
                  ),
                ]),
              ),
              _BarIcon(icon: Icons.equalizer_rounded, tooltip: 'Equalizer', onPressed: () => showEqBottomSheet(context)),
              _BarIcon(icon: Icons.keyboard_arrow_down_rounded, tooltip: 'Hide player bar', onPressed: onHide, width: 32),
              _BarIcon(icon: Icons.skip_previous_rounded, tooltip: 'Previous', size: 22, onPressed: pc.previous),
              IconButton.filled(
                icon: pc.buffering
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: cs.onPrimary))
                    : Icon(pc.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: pc.togglePlay,
              ),
              _BarIcon(icon: Icons.skip_next_rounded, tooltip: 'Next', size: 22, onPressed: pc.next),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Compact icon button so the bar keeps title space on narrow screens.
class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.icon, required this.tooltip, this.onPressed, this.size = 20, this.width = 34});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: 38,
        child: IconButton(
          icon: Icon(icon, size: size),
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          constraints: const BoxConstraints(),
          onPressed: onPressed,
        ),
      );
}

/// The discreet thing left behind when the mini player is slid away: playback
/// progress plus a grabber. Tap it (or swipe up) to bring the bar back.
class MiniPlayerHandle extends StatelessWidget {
  const MiniPlayerHandle({super.key, required this.onShow});
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final pc = context.watch<PlaybackController>();
    final cs = Theme.of(context).colorScheme;
    final total = pc.duration.inMilliseconds;
    final frac = total > 0 ? (pc.position.inMilliseconds / total).clamp(0.0, 1.0) : 0.0;
    return Semantics(
      button: true,
      label: 'Show the player bar',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onShow,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -120) onShow();
        },
        child: SizedBox(
          height: 24,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 2,
                  backgroundColor: cs.onSurface.withValues(alpha: 0.12),
                  color: cs.primary.withValues(alpha: 0.9),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: 34,
              height: 3,
              decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
            ),
          ]),
        ),
      ),
    );
  }
}
