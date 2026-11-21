import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../audio/playback_controller.dart';
import '../root_shell.dart';
import '../widgets/common.dart';

/// Persistent mini player: tap to expand, swipe up to expand, swipe
/// left/right to skip, progress line on top.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

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
        if ((d.primaryVelocity ?? 0) < -200) RootShell.openPlayer(context);
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
              IconButton(icon: const Icon(Icons.skip_previous_rounded), onPressed: pc.previous),
              IconButton.filled(
                icon: pc.buffering
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: cs.onPrimary))
                    : Icon(pc.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: pc.togglePlay,
              ),
              IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: pc.next),
            ]),
          ),
        ]),
      ),
    );
  }
}
