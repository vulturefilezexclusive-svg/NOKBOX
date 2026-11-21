import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../audio/playback_controller.dart';
import '../../data/models.dart';
import '../../library/library_controller.dart';
import '../../library/text_utils.dart';
import '../widgets/common.dart';

/// Collapsing header + play/shuffle + track list. Shared by album, artist,
/// genre, folder, playlist and generic lists.
class CollectionScaffold extends StatelessWidget {
  const CollectionScaffold({super.key, required this.title, required this.subtitle, required this.tracks, this.art, this.circleArt = false, this.actions = const [], this.header, this.numbered = false, this.discHeaders = false});
  final String title;
  final String subtitle;
  final List<Track> tracks;
  final String? art;
  final bool circleArt;
  final List<Widget> actions;
  final Widget? header;
  final bool numbered;
  final bool discHeaders;

  @override
  Widget build(BuildContext context) {
    final pc = context.read<PlaybackController>();
    final cs = Theme.of(context).colorScheme;
    final total = tracks.fold<int>(0, (a, t) => a + t.durationMs);
    final multiDisc = discHeaders && tracks.map((t) => t.discNo ?? 1).toSet().length > 1;
    final rows = <Widget>[];
    int? disc;
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      if (multiDisc && t.discNo != disc) {
        disc = t.discNo;
        rows.add(Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text('DISC ${disc ?? 1}', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: cs.primary))));
      }
      rows.add(TrackTile(track: t, index: numbered ? (t.trackNo ?? i + 1) : null, showArt: !numbered, queueContext: tracks, onTap: () => pc.playTracks(tracks, start: i, queueName: title)));
    }
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 300,
          actions: actions,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
            background: Stack(fit: StackFit.expand, children: [
              Opacity(opacity: 0.35, child: Artwork(uri: art, radius: 0, seed: title)),
              DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, cs.surface]))),
              Center(child: Padding(padding: const EdgeInsets.only(bottom: 40), child: Artwork(uri: art, size: 170, radius: 18, circle: circleArt, seed: title))),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$subtitle · ${tracks.length} tracks · ${formatDuration(Duration(milliseconds: total))}', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: tracks.isEmpty ? null : () => pc.playTracks(tracks, queueName: title), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Play'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.tonalIcon(onPressed: tracks.isEmpty ? null : () => pc.playTracks(tracks, shuffle: true, queueName: title), icon: const Icon(Icons.shuffle_rounded), label: const Text('Shuffle'))),
                const SizedBox(width: 6),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'next') pc.playNext(tracks);
                    if (v == 'queue') pc.addToQueue(tracks);
                    if (v == 'newq') pc.playTracks(tracks, newQueue: true, queueName: title);
                    if (v == 'pl') addToPlaylistFlow(context, tracks);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'next', child: Text('Play next')),
                    PopupMenuItem(value: 'queue', child: Text('Add to queue')),
                    PopupMenuItem(value: 'newq', child: Text('Play in new queue')),
                    PopupMenuItem(value: 'pl', child: Text('Add to playlist')),
                  ],
                ),
              ]),
              ?header,
            ]),
          ),
        ),
        SliverList.list(children: rows),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ]),
    );
  }
}

class AlbumScreen extends StatelessWidget {
  const AlbumScreen({super.key, required this.album});
  final Album album;
  @override
  Widget build(BuildContext context) => CollectionScaffold(
        title: album.title,
        subtitle: [album.artist, if (album.year != null) '${album.year}'].join(' · '),
        tracks: album.tracks,
        art: album.artUri,
        numbered: true,
        discHeaders: true,
      );
}

class ArtistScreen extends StatelessWidget {
  const ArtistScreen({super.key, required this.artist});
  final ArtistGroup artist;
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final albums = lib.albums.where((a) => a.tracks.any((t) => artist.tracks.contains(t))).toList();
    return CollectionScaffold(
      title: artist.name,
      subtitle: '${artist.albumCount} albums',
      tracks: lib.sorted(artist.tracks, TrackSort.album),
      art: artist.artUri,
      circleArt: true,
      header: albums.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                height: 170,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final a in albums)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: MediaCard(width: 120, title: a.title, subtitle: a.year?.toString(), art: a.artUri, onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AlbumScreen(album: a)))),
                    ),
                ]),
              ),
            ),
    );
  }
}

class TrackListScreen extends StatelessWidget {
  const TrackListScreen({super.key, required this.title, required this.tracks, this.subtitle = 'Collection', this.art});
  final String title;
  final List<Track> tracks;
  final String subtitle;
  final String? art;
  @override
  Widget build(BuildContext context) => CollectionScaffold(title: title, subtitle: subtitle, tracks: tracks, art: art ?? tracks.map((t) => t.artUri).whereType<String>().firstOrNull);
}

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key, required this.playlistId});
  final int playlistId;
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final pl = lib.playlists.where((p) => p.id == playlistId).firstOrNull;
    if (pl == null) return const Scaffold(body: Center(child: Text('Playlist deleted')));
    final tracks = lib.playlistTracks(pl);
    return CollectionScaffold(
      title: pl.name,
      subtitle: pl.description.isEmpty ? 'Playlist' : pl.description,
      tracks: tracks,
      art: tracks.map((t) => t.artUri).whereType<String>().firstOrNull,
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_rounded),
          onPressed: () async {
            final n = await promptText(context, title: 'Rename playlist', initial: pl.name);
            if (n != null && n.trim().isNotEmpty) lib.renamePlaylist(pl.id, n.trim());
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () {
            lib.deletePlaylist(pl.id);
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
