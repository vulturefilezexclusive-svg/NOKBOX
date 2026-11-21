import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app_globals.dart';
import '../../audio/playback_controller.dart';
import '../../data/models.dart';
import '../../library/library_controller.dart';
import '../../library/text_utils.dart';
import '../widgets/common.dart';
import 'detail_screens.dart';
import 'stats_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'Late night session';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Afternoon vibes';
    if (h < 21) return 'Evening rotation';
    return 'Night shift';
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final pc = context.read<PlaybackController>();
    final cs = Theme.of(context).colorScheme;
    final recent = nok.db.recentHistory(limit: 60);
    final seen = <String>{};
    final recentTracks = [for (final (t, _) in recent) if (seen.add(t.id)) t].take(20).toList();
    final most = nok.db.mostPlayed(sinceMs: DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch, limit: 20);
    final added = lib.sorted(lib.tracks.where((t) => t.isLocal).toList(), TrackSort.dateAdded, desc: true).take(20).toList();
    final total = nok.db.totalListenedMs();
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          titleSpacing: 16,
          title: const NokWordmark(size: 26, tagline: true),
          toolbarHeight: 68,
          actions: [
            IconButton(tooltip: 'Stats', icon: const Icon(Icons.insights_rounded), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const StatsScreen()))),
            IconButton(
              tooltip: 'Rescan library',
              icon: lib.scanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
              onPressed: lib.rescan,
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(colors: [cs.primary.withValues(alpha: 0.85), cs.primary.withValues(alpha: 0.25), Colors.black], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_greeting, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('${lib.tracks.length} tracks · ${lib.albums.length} albums · ${formatDuration(Duration(milliseconds: total))} listened',
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _Pill(icon: Icons.shuffle_rounded, label: 'Shuffle all', onTap: () => pc.playTracks(lib.tracks, shuffle: true, queueName: 'Shuffle all')),
                      _Pill(icon: Icons.favorite_rounded, label: 'Favorites', onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TrackListScreen(title: 'Favorites', tracks: lib.favoriteTracks)))),
                      _Pill(icon: Icons.history_rounded, label: 'History', onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const StatsScreen(initialTab: 1)))),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        if (lib.tracks.isEmpty && recentTracks.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.speaker_rounded,
              title: 'Load up the box',
              message: 'Drop music into Files › On My iPhone › NOKBOX, import from Library › Import, or hit the Feed tab to stream.',
            ),
          ),
        if (recentTracks.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Recently played')),
          SliverToBoxAdapter(child: _TrackCarousel(tracks: recentTracks, queueName: 'Recently played')),
        ],
        if (most.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Heavy rotation', subtitle: 'Most played · last 30 days')),
          SliverList.builder(
            itemCount: most.length.clamp(0, 6),
            itemBuilder: (_, i) {
              final (t, c, _) = most[i];
              return TrackTile(track: t, index: i + 1, trailing: Padding(padding: const EdgeInsets.only(right: 12), child: Text('$c×', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900))), onTap: () => pc.playTracks([for (final m in most) m.$1], start: i, queueName: 'Heavy rotation'));
            },
          ),
        ],
        if (added.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Fresh in the box', subtitle: 'Recently added')),
          SliverToBoxAdapter(child: _TrackCarousel(tracks: added, queueName: 'Recently added')),
        ],
        if (lib.albums.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionHeader('Albums', action: 'See all', onAction: () {})),
          SliverToBoxAdapter(
            child: Carousel(children: [
              for (final a in lib.albums.take(20))
                MediaCard(title: a.title, subtitle: a.artist, art: a.artUri, seed: a.key, onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AlbumScreen(album: a)))),
            ]),
          ),
        ],
        if (lib.artists.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionHeader('Artists')),
          SliverToBoxAdapter(
            child: Carousel(height: 150, children: [
              for (final a in ([...lib.artists]..sort((x, y) => y.tracks.length.compareTo(x.tracks.length))).take(20))
                MediaCard(width: 110, circle: true, title: a.name, subtitle: '${a.tracks.length} tracks', art: a.artUri, onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ArtistScreen(artist: a)))),
            ]),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16, color: Colors.white), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))]),
          ),
        ),
      );
}

class _TrackCarousel extends StatelessWidget {
  const _TrackCarousel({required this.tracks, required this.queueName});
  final List<Track> tracks;
  final String queueName;
  @override
  Widget build(BuildContext context) {
    final pc = context.read<PlaybackController>();
    return Carousel(children: [
      for (var i = 0; i < tracks.length; i++)
        GestureDetector(
          onLongPress: () => showTrackActions(context, tracks[i], queueContext: tracks),
          child: MediaCard(
            title: tracks[i].title,
            subtitle: tracks[i].displayArtist,
            art: tracks[i].artUri,
            seed: tracks[i].album,
            badge: tracks[i].isLocal ? null : SourceBadge(source: tracks[i].source),
            onTap: () => pc.playTracks(tracks, start: i, queueName: queueName),
          ),
        ),
    ]);
  }
}
