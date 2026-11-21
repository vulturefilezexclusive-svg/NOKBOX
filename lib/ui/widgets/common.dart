import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app_globals.dart';
import '../../audio/playback_controller.dart';
import '../../data/models.dart';
import '../../library/library_controller.dart';
import '../../library/text_utils.dart';

ImageProvider? artProvider(String? uri) {
  if (uri == null || uri.isEmpty) return null;
  if (uri.startsWith('http')) return NetworkImage(uri);
  final f = File(uri);
  return FileImage(f);
}

/// Artwork with graceful fallback: NB graffiti placeholder tinted by accent.
class Artwork extends StatelessWidget {
  const Artwork({super.key, required this.uri, this.size, this.radius = 12, this.icon, this.seed = '', this.circle = false});
  final String? uri;
  final double? size;
  final double radius;
  final IconData? icon;
  final String seed;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final img = artProvider(uri);
    final hue = (seed.hashCode % 40 - 20).toDouble();
    final base = HSVColor.fromColor(cs.primary);
    final c1 = base.withHue((base.hue + hue) % 360).withValue(0.55).toColor();
    Widget placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, Colors.black]),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, color: Colors.white70, size: (size ?? 48) * 0.42)
          : Text('NB', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, fontSize: (size ?? 48) * 0.34, letterSpacing: -1)),
    );
    final child = img == null
        ? placeholder
        : Image(
            image: img,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder,
            frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : placeholder,
          );
    final sized = SizedBox(width: size, height: size, child: child);
    return circle ? ClipOval(child: sized) : ClipRRect(borderRadius: BorderRadius.circular(radius), child: sized);
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.action, this.onAction, this.padding = const EdgeInsets.fromLTRB(16, 20, 8, 8)});
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(children: [
        Container(width: 4, height: 20, decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.textTheme.titleLarge?.copyWith(fontSize: 19)),
            if (subtitle != null) Text(subtitle!, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
          ]),
        ),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary.withValues(alpha: 0.12)),
            child: Icon(icon, size: 44, color: cs.primary),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65))),
          ],
          if (action != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.add_rounded), label: Text(action!)),
          ],
        ]),
      ),
    );
  }
}

/// Wordmark: NOKBOX in heavy italic with red underline accent.
class NokWordmark extends StatelessWidget {
  const NokWordmark({super.key, this.size = 26, this.tagline = false});
  final double size;
  final bool tagline;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      RichText(
        text: TextSpan(style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: -0.5, color: cs.onSurface), children: [
          const TextSpan(text: 'NOK'),
          TextSpan(text: 'BOX', style: TextStyle(color: cs.primary)),
        ]),
      ),
      if (tagline) Text('A MUZIK JUNKIE PARADISE', style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w800, letterSpacing: 2.2, color: cs.onSurface.withValues(alpha: 0.7))),
    ]);
  }
}

class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track, this.onTap, this.index, this.trailing, this.showArt = true, this.dense = false, this.queueContext});
  final Track track;
  final VoidCallback? onTap;
  final int? index;
  final Widget? trailing;
  final bool showArt;
  final bool dense;
  final List<Track>? queueContext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pc = context.watch<PlaybackController>();
    final isCurrent = pc.current?.id == track.id;
    final sub = [
      track.displayArtist,
      if (track.album.isNotEmpty && !dense) track.album,
      if (track.durationMs > 0) formatDuration(track.duration),
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      onLongPress: () => showTrackActions(context, track, queueContext: queueContext),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 5 : 7),
        child: Row(children: [
          if (index != null)
            SizedBox(
              width: 30,
              child: isCurrent
                  ? Icon(pc.playing ? Icons.graphic_eq_rounded : Icons.pause_rounded, color: cs.primary, size: 20)
                  : Text('$index', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontWeight: FontWeight.w700)),
            ),
          if (showArt) ...[
            Stack(children: [
              Artwork(uri: track.artUri, size: dense ? 42 : 50, radius: 10, seed: track.album, icon: track.isVideo ? Icons.movie_rounded : null),
              if (isCurrent && index == null)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                    child: Icon(pc.playing ? Icons.graphic_eq_rounded : Icons.pause_rounded, color: cs.primary),
                  ),
                ),
            ]),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: isCurrent ? cs.primary : null)),
              const SizedBox(height: 2),
              Row(children: [
                if (!track.isLocal) ...[SourceBadge(source: track.source), const SizedBox(width: 6)],
                if (track.isVideo) ...[Icon(Icons.movie_rounded, size: 13, color: cs.onSurface.withValues(alpha: 0.55)), const SizedBox(width: 4)],
                Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.6)))),
              ]),
            ]),
          ),
          trailing ??
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () => showTrackActions(context, track, queueContext: queueContext),
              ),
        ]),
      ),
    );
  }
}

class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source});
  final String source;
  @override
  Widget build(BuildContext context) {
    final p = nok.registry.byId(source);
    final color = p?.brandColor ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(4)),
      child: Text((p?.name ?? source).toUpperCase(), style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.6)),
    );
  }
}

/// Square card used in carousels / grids.
class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.title, this.subtitle, this.art, this.onTap, this.width = 150, this.circle = false, this.seed = '', this.icon, this.badge});
  final String title;
  final String? subtitle;
  final String? art;
  final VoidCallback? onTap;
  final double width;
  final bool circle;
  final String seed;
  final IconData? icon;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(crossAxisAlignment: circle ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
          Stack(children: [
            Artwork(uri: art, size: width, radius: 14, circle: circle, seed: seed.isEmpty ? title : seed, icon: icon),
            if (badge != null) Positioned(left: 6, top: 6, child: badge!),
          ]),
          const SizedBox(height: 8),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: circle ? TextAlign.center : TextAlign.start, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (subtitle != null)
            Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: circle ? TextAlign.center : TextAlign.start, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }
}

class Carousel extends StatelessWidget {
  const Carousel({super.key, required this.children, this.height = 205});
  final List<Widget> children;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => children[i],
        ),
      );
}

void snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

Future<String?> promptText(BuildContext context, {required String title, String initial = '', String hint = '', String ok = 'Save'}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint), onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ok)),
      ],
    ),
  );
}

Future<void> addToPlaylistFlow(BuildContext context, List<Track> tracks) async {
  final lib = context.read<LibraryController>();
  final pick = await showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Add to playlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
        ListTile(leading: const Icon(Icons.add_rounded), title: const Text('New playlist'), onTap: () => Navigator.pop(ctx, -1)),
        for (final p in lib.playlists)
          ListTile(leading: const Icon(Icons.queue_music_rounded), title: Text(p.name), subtitle: Text('${p.trackIds.length} tracks'), onTap: () => Navigator.pop(ctx, p.id)),
      ]),
    ),
  );
  if (pick == null || !context.mounted) return;
  var id = pick;
  if (pick == -1) {
    final name = await promptText(context, title: 'New playlist', hint: 'Playlist name');
    if (name == null || name.trim().isEmpty) return;
    id = lib.createPlaylist(name.trim());
  }
  lib.addToPlaylist(id, tracks);
  if (context.mounted) snack(context, 'Added ${tracks.length} to playlist');
}

/// Long-press / overflow menu for a track.
Future<void> showTrackActions(BuildContext context, Track t, {List<Track>? queueContext}) {
  final pc = context.read<PlaybackController>();
  final lib = context.read<LibraryController>();
  final cap = nok.downloads.capabilityOf(t);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Artwork(uri: t.artUri, size: 52, seed: t.album),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${t.displayArtist} · ${t.displayAlbum}', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              icon: Icon(lib.isFavorite(t.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: Theme.of(ctx).colorScheme.primary),
              onPressed: () {
                lib.toggleFavorite(t);
                Navigator.pop(ctx);
              },
            ),
          ),
          const Divider(),
          _act(ctx, Icons.play_arrow_rounded, 'Play now', () => pc.playTracks(queueContext ?? [t], start: queueContext?.indexOf(t) ?? 0)),
          _act(ctx, Icons.playlist_play_rounded, 'Play next', () => pc.playNext([t])),
          _act(ctx, Icons.queue_rounded, 'Add to queue', () => pc.addToQueue([t])),
          _act(ctx, Icons.layers_rounded, 'Play in a new queue', () => pc.playTracks([t], newQueue: true)),
          _act(ctx, Icons.playlist_add_rounded, 'Add to playlist…', () => addToPlaylistFlow(context, [t])),
          if (cap != DownloadCapability.none)
            _act(ctx, cap == DownloadCapability.allowed ? Icons.download_rounded : Icons.open_in_new_rounded,
                cap == DownloadCapability.allowed ? 'Download' : 'Download on official page', () async {
              final m = await nok.downloads.request(t);
              if (context.mounted) snack(context, m);
            }),
          _act(ctx, Icons.info_outline_rounded, 'Track info & tags', () => showTagInfo(context, t)),
        ]),
      ),
    ),
  );
}

Widget _act(BuildContext ctx, IconData icon, String label, VoidCallback onTap) => ListTile(
      leading: Icon(icon),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
    );

Future<void> showTagInfo(BuildContext context, Track t) {
  final rows = <(String, String)>[
    ('Title', t.title),
    ('Artist', t.displayArtist),
    ('Album', t.displayAlbum),
    if (t.albumArtist.isNotEmpty) ('Album artist', t.albumArtist),
    if (t.genre.isNotEmpty) ('Genre', t.genre),
    if (t.year != null) ('Year', '${t.year}'),
    if (t.trackNo != null) ('Track', '${t.trackNo}'),
    if (t.discNo != null) ('Disc', '${t.discNo}'),
    ('Duration', formatDuration(t.duration)),
    if (t.format.isNotEmpty) ('Format', t.format),
    if (t.bitrate != null) ('Bitrate', '${t.bitrate! > 10000 ? t.bitrate! ~/ 1000 : t.bitrate} kbps'),
    if (t.sampleRate != null) ('Sample rate', '${t.sampleRate} Hz'),
    if (t.sizeBytes > 0) ('Size', formatBytes(t.sizeBytes)),
    ('Source', t.source),
    if (t.isrc != null) ('ISRC', t.isrc!),
    if (t.mbid != null) ('MusicBrainz', t.mbid!),
    ('Plays', '${nok.db.playCount(t.id)}'),
    ('Downloads', switch (nok.downloads.capabilityOf(t)) {
      DownloadCapability.allowed => 'Allowed',
      DownloadCapability.viaOfficialPage => 'Via official page',
      DownloadCapability.none => t.isLocal ? 'Local file' : 'Stream only',
    }),
    ('Location', t.uri),
  ];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
        Row(children: [
          Artwork(uri: t.artUri, size: 84, seed: t.album),
          const SizedBox(width: 14),
          Expanded(child: Text(t.title, style: Theme.of(ctx).textTheme.titleLarge)),
        ]),
        const SizedBox(height: 14),
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 110, child: Text(k, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600))),
              Expanded(child: SelectableText(v, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
        const SizedBox(height: 8),
        Text('Batch tag editing & rename-from-template arrive in v1.', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5))),
      ]),
    ),
  );
}
