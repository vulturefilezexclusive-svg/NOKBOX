import 'package:material_ui/material_ui.dart';

import '../../app_globals.dart';
import '../../sources/youtube/sponsorblock.dart';

String compactCount(int n) {
  if (n >= 1000000000) return '${(n / 1e9).toStringAsFixed(1)}B';
  if (n >= 1000000) return '${(n / 1e6).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1e3).toStringAsFixed(1)}K';
  return '$n';
}

/// Likes / dislikes (Return YouTube Dislike) + views for a YouTube video.
class YoutubeVotesRow extends StatelessWidget {
  const YoutubeVotesRow({super.key, required this.videoId});
  final String videoId;

  @override
  Widget build(BuildContext context) {
    if (!nok.settings.get('ryd.enabled', true)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<RydVotes?>(
      key: ValueKey(videoId),
      future: nok.ryd.votes(videoId),
      builder: (context, snap) {
        final v = snap.data;
        if (v == null) return const SizedBox(height: 6);
        final total = v.likes + v.dislikes;
        final ratio = total == 0 ? 0.0 : v.likes / total;
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const Icon(Icons.thumb_up_alt_rounded, size: 16),
            const SizedBox(width: 4),
            Text(compactCount(v.likes), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: ratio, minHeight: 4, color: cs.primary, backgroundColor: cs.onSurface.withValues(alpha: 0.25)),
              ),
            ),
            const SizedBox(width: 8),
            Text(compactCount(v.dislikes), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            const SizedBox(width: 4),
            const Icon(Icons.thumb_down_alt_rounded, size: 16),
            const SizedBox(width: 10),
            Text('${compactCount(v.views)} views', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
            Tooltip(message: 'Dislikes via Return YouTube Dislike (estimated)', child: Icon(Icons.info_outline_rounded, size: 14, color: cs.onSurface.withValues(alpha: 0.5))),
          ]),
        );
      },
    );
  }
}
