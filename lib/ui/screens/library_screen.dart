import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../audio/playback_controller.dart';
import '../../core/settings.dart';
import '../../library/library_controller.dart';
import '../widgets/common.dart';
import 'detail_screens.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  static Future<void> importFiles(BuildContext context) async {
    final lib = context.read<LibraryController>();
    final r = await FilePicker.pickFiles(type: FileType.any);
    if (r.isEmpty) return;
    final n = await lib.importFiles(r.map((f) => f.path).whereType<String>().toList());
    if (context.mounted) snack(context, 'Imported $n files');
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          actions: [
            IconButton(tooltip: 'Import files', icon: const Icon(Icons.file_download_outlined), onPressed: () => importFiles(context)),
            IconButton(
              tooltip: 'Rescan',
              icon: lib.scanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
              onPressed: () async {
                await lib.rescan();
                if (context.mounted && lib.lastScanSummary != null) snack(context, lib.lastScanSummary!);
              },
            ),
          ],
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: 'Tracks ${lib.tracks.where((t) => !t.isVideo).length}'),
            Tab(text: 'Albums ${lib.albums.length}'),
            Tab(text: 'Artists ${lib.artists.length}'),
            Tab(text: 'Genres ${lib.genres.length}'),
            Tab(text: 'Folders ${lib.folders.length}'),
            Tab(text: 'Playlists ${lib.playlists.length}'),
            Tab(text: 'Videos ${lib.videos.length}'),
          ]),
        ),
        body: const TabBarView(children: [
          _TracksTab(),
          _AlbumsTab(),
          _ArtistsTab(),
          _GenresTab(),
          _FoldersTab(),
          PlaylistsTab(),
          _VideosTab(),
        ]),
      ),
    );
  }
}

class _TracksTab extends StatelessWidget {
  const _TracksTab();
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final s = context.watch<SettingsStore>();
    final pc = context.read<PlaybackController>();
    final sort = TrackSort.values.firstWhere((e) => e.name == s.librarySort, orElse: () => TrackSort.title);
    final tracks = lib.sorted(lib.tracks.where((t) => !t.isVideo).toList(), sort, desc: s.librarySortDesc);
    if (tracks.isEmpty) {
      return EmptyState(
        icon: Icons.music_note_rounded,
        title: 'No tracks yet',
        message: 'Put audio files in Files › On My iPhone › NOKBOX (watched automatically) or import them.',
        action: 'Import files',
        onAction: () => LibraryScreen.importFiles(context),
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
        child: Row(children: [
          FilledButton.tonalIcon(onPressed: () => pc.playTracks(tracks, shuffle: true, queueName: 'All tracks'), icon: const Icon(Icons.shuffle_rounded), label: const Text('Shuffle')),
          const Spacer(),
          PopupMenuButton<TrackSort>(
            initialValue: sort,
            onSelected: (v) => s.set('librarySort', v.name),
            child: Row(children: [const Icon(Icons.sort_rounded, size: 18), const SizedBox(width: 4), Text(sort.name, style: const TextStyle(fontWeight: FontWeight.w700))]),
            itemBuilder: (_) => [for (final v in TrackSort.values) PopupMenuItem(value: v, child: Text(v.name))],
          ),
          IconButton(icon: Icon(s.librarySortDesc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded), onPressed: () => s.set('librarySortDesc', !s.librarySortDesc)),
        ]),
      ),
      Expanded(
        child: Scrollbar(
          interactive: true,
          child: ListView.builder(
            itemCount: tracks.length,
            itemExtent: 66,
            itemBuilder: (_, i) => TrackTile(track: tracks[i], queueContext: tracks, onTap: () => pc.playTracks(tracks, start: i, queueName: 'All tracks')),
          ),
        ),
      ),
    ]);
  }
}

class _AlbumsTab extends StatelessWidget {
  const _AlbumsTab();
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    if (lib.albums.isEmpty) return const EmptyState(icon: Icons.album_rounded, title: 'No albums');
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.78),
      itemCount: lib.albums.length,
      itemBuilder: (_, i) {
        final a = lib.albums[i];
        return LayoutBuilder(
          builder: (c, box) => MediaCard(
            width: box.maxWidth,
            title: a.title,
            subtitle: '${a.artist}${a.discs.length > 1 ? ' · ${a.discs.length} discs' : ''}',
            art: a.artUri,
            seed: a.key,
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AlbumScreen(album: a))),
          ),
        );
      },
    );
  }
}

class _ArtistsTab extends StatelessWidget {
  const _ArtistsTab();
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    if (lib.artists.isEmpty) return const EmptyState(icon: Icons.person_rounded, title: 'No artists');
    return ListView.builder(
      itemCount: lib.artists.length,
      itemBuilder: (_, i) {
        final a = lib.artists[i];
        return ListTile(
          leading: Artwork(uri: a.artUri, size: 48, circle: true, seed: a.name),
          title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${a.albumCount} albums · ${a.tracks.length} tracks'),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ArtistScreen(artist: a))),
        );
      },
    );
  }
}

class _GenresTab extends StatelessWidget {
  const _GenresTab();
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final cs = Theme.of(context).colorScheme;
    if (lib.genres.isEmpty) return const EmptyState(icon: Icons.category_rounded, title: 'No genres');
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 2.2),
      itemCount: lib.genres.length,
      itemBuilder: (_, i) {
        final g = lib.genres[i];
        final hsv = HSVColor.fromColor(cs.primary);
        final c = hsv.withHue((hsv.hue + i * 37) % 360).withValue(0.6).toColor();
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TrackListScreen(title: g.name, tracks: g.tracks, subtitle: 'Genre'))),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: [c, Colors.black])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(g.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
              Text('${g.tracks.length} tracks', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        );
      },
    );
  }
}

class _FoldersTab extends StatelessWidget {
  const _FoldersTab();
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    if (lib.folders.isEmpty) return const EmptyState(icon: Icons.folder_rounded, title: 'No folders');
    return ListView.builder(
      itemCount: lib.folders.length,
      itemBuilder: (_, i) {
        final f = lib.folders[i];
        return ListTile(
          leading: const Icon(Icons.folder_rounded, size: 34),
          title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${f.tracks.length} tracks · ${f.path}', maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TrackListScreen(title: f.name, tracks: f.tracks, subtitle: 'Folder'))),
        );
      },
    );
  }
}

class PlaylistsTab extends StatelessWidget {
  const PlaylistsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    return ListView(children: [
      ListTile(
        leading: const CircleAvatar(child: Icon(Icons.add_rounded)),
        title: const Text('New playlist', style: TextStyle(fontWeight: FontWeight.w800)),
        onTap: () async {
          final n = await promptText(context, title: 'New playlist', hint: 'Name');
          if (n != null && n.trim().isNotEmpty) lib.createPlaylist(n.trim());
        },
      ),
      ListTile(
        leading: const CircleAvatar(child: Icon(Icons.favorite_rounded)),
        title: const Text('Favorites', style: TextStyle(fontWeight: FontWeight.w800)),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TrackListScreen(title: 'Favorites', tracks: lib.favoriteTracks))),
      ),
      const Divider(),
      for (final p in lib.playlists)
        ListTile(
          leading: Artwork(uri: lib.playlistTracks(p).map((t) => t.artUri).whereType<String>().firstOrNull, size: 48, seed: p.name, icon: Icons.queue_music_rounded),
          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${p.trackIds.length} tracks'),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PlaylistScreen(playlistId: p.id))),
        ),
    ]);
  }
}

class _VideosTab extends StatelessWidget {
  const _VideosTab();
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final pc = context.read<PlaybackController>();
    final v = lib.videos;
    if (v.isEmpty) return const EmptyState(icon: Icons.movie_rounded, title: 'No videos', message: 'Video files in your NOKBOX folder show up here.');
    return ListView.builder(
      itemCount: v.length,
      itemBuilder: (_, i) => TrackTile(
        track: v[i],
        queueContext: v,
        onTap: () {
          if (!pc.videoMode) pc.toggleVideoMode();
          pc.playTracks(v, start: i, queueName: 'Videos');
        },
      ),
    );
  }
}

/// Bottom-nav "Playlists" tab.
class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Playlists')), body: const PlaylistsTab());
}
