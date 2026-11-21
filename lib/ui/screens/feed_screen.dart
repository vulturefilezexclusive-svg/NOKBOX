import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../audio/playback_controller.dart';
import '../../core/settings.dart';
import '../../data/models.dart';
import '../../sources/providers/custom_provider.dart';
import '../../sources/source_provider.dart';
import '../../sources/source_registry.dart';
import '../widgets/common.dart';

/// Online feed. The provider comes from Settings › Source (empty = YouTube).
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  Future<List<FeedSection>>? _future;
  SourceProvider? _provider;

  void _load(SourceProvider p, {bool force = false}) {
    if (!force && identical(p, _provider) && _future != null) return;
    _provider = p;
    _future = p.browse();
  }

  Future<void> _changeSource(BuildContext context) async {
    final s = context.read<SettingsStore>();
    final reg = context.read<SourceRegistry>();
    final pick = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = TextEditingController(text: s.sourceField);
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Feed source', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Type any service name or paste a URL (stream, M3U, RSS, website). Leave empty for YouTube.'),
            const SizedBox(height: 12),
            TextField(controller: c, decoration: const InputDecoration(hintText: 'e.g. radio, podcasts, bandcamp, https://…'), onSubmitted: (v) => Navigator.pop(ctx, v)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in reg.builtIns) ActionChip(avatar: Icon(p.icon, size: 16, color: p.brandColor), label: Text(p.name), onPressed: () => Navigator.pop(ctx, p.id == SourceIds.youtube ? '' : p.name)),
            ]),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Use this source'))),
          ]),
        );
      },
    );
    if (pick != null) s.sourceField = pick;
  }

  @override
  Widget build(BuildContext context) {
    final reg = context.watch<SourceRegistry>();
    context.watch<SettingsStore>();
    final p = reg.feedProvider;
    _load(p);
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Icon(p.icon, color: p.brandColor),
          const SizedBox(width: 10),
          Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: () => setState(() => _load(p, force: true))),
          TextButton.icon(onPressed: () => _changeSource(context), icon: const Icon(Icons.swap_horiz_rounded), label: const Text('Source')),
        ],
      ),
      body: p.webUrl != null && p is WebSourceProvider
          ? _WebSource(url: p.webUrl!)
          : p.setupHint != null
              ? EmptyState(icon: Icons.key_rounded, title: '${p.name} needs setup', message: p.setupHint, action: 'Change source', onAction: () => _changeSource(context))
              : FutureBuilder<List<FeedSection>>(
                  future: _future,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) return const _FeedSkeleton();
                    if (snap.hasError) {
                      if (snap.error is WebFallbackRequired && p is CustomUrlProvider) return _WebSource(url: p.url);
                      return EmptyState(icon: Icons.wifi_off_rounded, title: 'Feed unavailable', message: '${snap.error}', action: 'Retry', onAction: () => setState(() => _load(p, force: true)));
                    }
                    final sections = snap.data ?? const [];
                    if (sections.isEmpty) return const EmptyState(icon: Icons.inbox_rounded, title: 'Nothing here yet');
                    return RefreshIndicator(
                      onRefresh: () async {
                        setState(() => _load(p, force: true));
                        await _future;
                      },
                      child: ListView(children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Text(p.tagline, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                        ),
                        for (final s in sections) FeedSectionView(provider: p, section: s),
                        const SizedBox(height: 30),
                      ]),
                    );
                  },
                ),
    );
  }
}

class FeedSectionView extends StatelessWidget {
  const FeedSectionView({super.key, required this.provider, required this.section});
  final SourceProvider provider;
  final FeedSection section;

  void _open(BuildContext context, int i) {
    final t = section.items[i];
    if (provider.isCollection(t)) {
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CollectionFeedScreen(provider: provider, collection: t)));
      return;
    }
    final playable = section.items.where((x) => !provider.isCollection(x)).toList();
    context.read<PlaybackController>().playTracks(playable, start: playable.indexOf(t), queueName: '${provider.name} · ${section.title}');
  }

  @override
  Widget build(BuildContext context) {
    // A section with no items used to reach `section.items.first` for its
    // carousel height and throw (an empty shelf from any provider is normal:
    // a search with no hits, a filtered feed, a feed that answered oddly).
    if (section.items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(section.title, subtitle: section.subtitle),
      if (section.layout == FeedLayout.list)
        for (var i = 0; i < section.items.length.clamp(0, 8); i++) TrackTile(track: section.items[i], queueContext: section.items, onTap: () => _open(context, i))
      else
        Carousel(
          height: section.items.first.isVideo ? 190 : 205,
          children: [
            for (var i = 0; i < section.items.length; i++)
              GestureDetector(
                onLongPress: provider.isCollection(section.items[i]) ? null : () => showTrackActions(context, section.items[i], queueContext: section.items),
                child: section.items[i].isVideo
                    ? _VideoCard(track: section.items[i], onTap: () => _open(context, i))
                    : MediaCard(title: section.items[i].title, subtitle: section.items[i].displayArtist, art: section.items[i].artUri, onTap: () => _open(context, i)),
              ),
          ],
        ),
    ]);
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 240,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 240, height: 135, child: Artwork(uri: track.artUri, radius: 14, icon: Icons.smart_display_rounded))),
            if (track.durationMs > 0)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
                  child: Text('${track.duration.inMinutes}:${track.duration.inSeconds.remainder(60).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(track.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainerHigh;
    return ListView(children: [
      for (var s = 0; s < 3; s++) ...[
        Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 10), child: Container(width: 160, height: 18, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)))),
        SizedBox(
          height: 150,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            for (var i = 0; i < 4; i++) Container(width: 150, margin: const EdgeInsets.only(right: 12), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(14))),
          ]),
        ),
      ],
    ]);
  }
}

/// Podcast show / archive item expanded into its episodes / files.
class CollectionFeedScreen extends StatelessWidget {
  const CollectionFeedScreen({super.key, required this.provider, required this.collection});
  final SourceProvider provider;
  final Track collection;
  @override
  Widget build(BuildContext context) {
    final pc = context.read<PlaybackController>();
    return Scaffold(
      appBar: AppBar(title: Text(collection.title, overflow: TextOverflow.ellipsis)),
      body: FutureBuilder<List<Track>>(
        future: provider.expand(collection),
        builder: (context, snap) {
          if (!snap.hasData) return snap.hasError ? EmptyState(icon: Icons.error_outline_rounded, title: 'Failed to load', message: '${snap.error}') : const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Artwork(uri: collection.artUri, size: 110, seed: collection.title),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(collection.title, style: Theme.of(context).textTheme.titleLarge),
                    Text(collection.artist),
                    const SizedBox(height: 8),
                    FilledButton.icon(onPressed: items.isEmpty ? null : () => pc.playTracks(items, queueName: collection.title), icon: const Icon(Icons.play_arrow_rounded), label: Text('Play ${items.length}')),
                  ]),
                ),
              ]),
            ),
            for (var i = 0; i < items.length; i++) TrackTile(track: items[i], queueContext: items, onTap: () => pc.playTracks(items, start: i, queueName: collection.title)),
          ]);
        },
      ),
    );
  }
}

/// Service's own site in a web view (stream only, no extraction).
class _WebSource extends StatefulWidget {
  const _WebSource({required this.url});
  final Uri url;
  @override
  State<_WebSource> createState() => _WebSourceState();
}

class _WebSourceState extends State<_WebSource> {
  WebViewController? _c;
  @override
  void initState() {
    super.initState();
    try {
      _c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(widget.url);
    } catch (_) {
      _c = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_c == null) return EmptyState(icon: Icons.public_rounded, title: 'Web view unavailable', message: widget.url.toString());
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Text('Web source · stream only · ${widget.url.host}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ),
      Expanded(child: WebViewWidget(controller: _c!)),
    ]);
  }
}
