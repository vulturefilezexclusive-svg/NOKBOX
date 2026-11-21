import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app_globals.dart';
import '../../audio/playback_controller.dart';
import '../../data/models.dart';
import '../../library/library_controller.dart';
import '../widgets/common.dart';
import 'detail_screens.dart';
import 'feed_screen.dart';

/// Unified search: library (FTS5 + typo-tolerant) and every enabled online
/// source in parallel, with filter chips.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _c = TextEditingController();
  Timer? _debounce;
  String _q = '';
  String _filter = 'all';
  final Map<String, List<Track>> _online = {};
  final Map<String, bool> _loading = {};

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _q = v.trim());
      _searchOnline();
    });
  }

  Future<void> _searchOnline() async {
    final q = _q;
    _online.clear();
    if (q.length < 2) return;
    for (final p in nok.registry.builtIns) {
      if (p.setupHint != null) continue;
      _loading[p.id] = true;
      p.search(q).then((r) {
        if (!mounted || q != _q) return;
        setState(() {
          _online[p.id] = r;
          _loading[p.id] = false;
        });
      }).catchError((_) {
        if (mounted) setState(() => _loading[p.id] = false);
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    final pc = context.read<PlaybackController>();
    final local = _q.isEmpty ? <Track>[] : lib.search(_q);
    final ql = _q.toLowerCase();
    final albums = _q.isEmpty ? <Album>[] : lib.albums.where((a) => a.title.toLowerCase().contains(ql) || a.artist.toLowerCase().contains(ql)).take(12).toList();
    final artists = _q.isEmpty ? <ArtistGroup>[] : lib.artists.where((a) => a.name.toLowerCase().contains(ql)).take(12).toList();
    final providers = nok.registry.builtIns.where((p) => p.setupHint == null).toList();
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: TextField(
          controller: _c,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Songs, artists, albums, lyrics…',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _c.clear();
                      _onChanged('');
                    },
                  ),
          ),
        ),
      ),
      body: _q.isEmpty
          ? const EmptyState(icon: Icons.manage_search_rounded, title: 'Search everything', message: 'Your library and every connected source at once. Typos are OK.')
          : ListView(children: [
              SizedBox(
                height: 48,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final f in ['all', 'library', ...providers.map((p) => p.id)])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f == 'all' ? 'All' : f == 'library' ? 'Library' : nok.registry.byId(f)!.name),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ]),
              ),
              if (_filter == 'all' || _filter == 'library') ...[
                if (artists.isNotEmpty) ...[
                  const SectionHeader('Artists'),
                  Carousel(height: 150, children: [
                    for (final a in artists)
                      MediaCard(width: 110, circle: true, title: a.name, art: a.artUri, onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ArtistScreen(artist: a)))),
                  ]),
                ],
                if (albums.isNotEmpty) ...[
                  const SectionHeader('Albums'),
                  Carousel(children: [
                    for (final a in albums)
                      MediaCard(title: a.title, subtitle: a.artist, art: a.artUri, onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AlbumScreen(album: a)))),
                  ]),
                ],
                SectionHeader('In your library', subtitle: '${local.length} results'),
                for (var i = 0; i < local.length.clamp(0, _filter == 'library' ? 200 : 8); i++)
                  TrackTile(track: local[i], queueContext: local, onTap: () => pc.playTracks(local, start: i, queueName: 'Search: $_q')),
              ],
              for (final p in providers)
                if (_filter == 'all' || _filter == p.id) ...[
                  SectionHeader(p.name, subtitle: p.tagline),
                  if (_loading[p.id] == true) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
                  for (final t in (_online[p.id] ?? const <Track>[]).take(_filter == p.id ? 50 : 5))
                    TrackTile(
                      track: t,
                      queueContext: _online[p.id],
                      onTap: () => p.isCollection(t)
                          ? Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CollectionFeedScreen(provider: p, collection: t)))
                          : pc.playTracks(_online[p.id]!.where((x) => !p.isCollection(x)).toList(), start: _online[p.id]!.where((x) => !p.isCollection(x)).toList().indexOf(t), queueName: '${p.name}: $_q'),
                    ),
                ],
              const SizedBox(height: 30),
            ]),
    );
  }
}
