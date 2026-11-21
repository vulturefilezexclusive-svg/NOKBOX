import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_globals.dart';
import '../audio/playback_controller.dart';
import '../core/diagnostics.dart';
import '../core/theme/theme_controller.dart';
import 'player/full_player.dart';
import 'player/mini_player.dart';
import 'screens/feed_screen.dart';
import 'screens/library_screen.dart';
import 'screens/search_screen.dart';
import 'settings/settings_screen.dart';
import 'widgets/common.dart';

/// App frame: 5 tabs, each with its own navigator so the mini player and
/// nav bar stay visible while drilling into albums/artists.
class RootShell extends StatefulWidget {
  const RootShell({super.key});
  static final navKeys = List.generate(5, (_) => GlobalKey<NavigatorState>());
  static void openPlayer(BuildContext context) => Navigator.of(context, rootNavigator: true).push(FullPlayer.route());

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  int _tab = 0;
  StreamSubscription<String>? _msgs;
  String? _lastArt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _msgs = nok.playback.messages.listen((m) {
      if (mounted) snack(context, m);
    });
    nok.playback.addListener(_onTrack);
  }

  void _onTrack() {
    final c = nok.playback.current;
    if (c?.artUri != _lastArt) {
      _lastArt = c?.artUri;
      context.read<ThemeController>().updateFromArtwork(artProvider(_lastArt));
      nok.lyrics.load(c);
    } else if (c != null && nok.lyrics.lyrics == null && !nok.lyrics.loading) {
      nok.lyrics.load(c);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) nok.library.rescan();
    if (state == AppLifecycleState.detached) Diag.cleanExit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _msgs?.cancel();
    nok.playback.removeListener(_onTrack);
    super.dispose();
  }

  Widget _tabNav(int i, Widget root) => Navigator(
        key: RootShell.navKeys[i],
        onGenerateRoute: (s) => MaterialPageRoute(builder: (_) => root, settings: s),
      );

  @override
  Widget build(BuildContext context) {
    final hasTrack = context.select<PlaybackController, bool>((p) => p.current != null);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        final nav = RootShell.navKeys[_tab].currentState;
        if (nav != null && nav.canPop()) nav.pop();
      },
      child: Scaffold(
        body: IndexedStack(index: _tab, children: [
          _tabNav(0, const FeedScreen()),
          _tabNav(1, const LibraryScreen()),
          _tabNav(2, const SearchScreen()),
          _tabNav(3, const PlaylistsScreen()),
          _tabNav(4, const SettingsScreen()),
        ]),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          if (hasTrack) const MiniPlayer(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) {
              if (i == _tab) {
                RootShell.navKeys[i].currentState?.popUntil((r) => r.isFirst);
              }
              setState(() => _tab = i);
            },
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music_rounded), label: 'Library'),
              NavigationDestination(icon: Icon(Icons.search_rounded), selectedIcon: Icon(Icons.manage_search_rounded), label: 'Search'),
              NavigationDestination(icon: Icon(Icons.queue_music_outlined), selectedIcon: Icon(Icons.queue_music_rounded), label: 'Playlists'),
              NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'Settings'),
            ],
          ),
        ]),
      ),
    );
  }
}
