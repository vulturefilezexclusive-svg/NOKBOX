import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app_globals.dart';
import '../../audio/playback_controller.dart';
import '../../library/text_utils.dart';
import '../widgets/common.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _range = 30;

  @override
  Widget build(BuildContext context) {
    final pc = context.read<PlaybackController>();
    final cs = Theme.of(context).colorScheme;
    final since = _range == 0 ? null : DateTime.now().subtract(Duration(days: _range)).millisecondsSinceEpoch;
    final top = nok.db.mostPlayed(sinceMs: since, limit: 50);
    final artists = nok.db.topArtists(sinceMs: since);
    final byDay = nok.db.listeningByDay(days: 14);
    final history = nok.db.recentHistory(limit: 200);
    final maxDay = byDay.values.fold<int>(1, (a, b) => b > a ? b : a);
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stats & history'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'clear') {
                  nok.db.clearHistory();
                  setState(() {});
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'clear', child: Text('Clear history'))],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Stats'), Tab(text: 'History')]),
        ),
        body: TabBarView(children: [
          ListView(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<int>(
                segments: const [ButtonSegment(value: 7, label: Text('7d')), ButtonSegment(value: 30, label: Text('30d')), ButtonSegment(value: 365, label: Text('Year')), ButtonSegment(value: 0, label: Text('All'))],
                selected: {_range},
                onSelectionChanged: (s) => setState(() => _range = s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Total listening', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
                    Text(formatDuration(Duration(milliseconds: nok.db.totalListenedMs())), style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 90,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        for (var i = 13; i >= 0; i--)
                          Builder(builder: (_) {
                            final d = DateTime.now().subtract(Duration(days: i));
                            final v = byDay[DateTime(d.year, d.month, d.day)] ?? 0;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                                  Container(height: 4 + 70 * v / maxDay, decoration: BoxDecoration(color: cs.primary.withValues(alpha: v == 0 ? 0.2 : 1), borderRadius: BorderRadius.circular(4))),
                                  const SizedBox(height: 4),
                                  Text('${d.day}', style: const TextStyle(fontSize: 9)),
                                ]),
                              ),
                            );
                          }),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            if (artists.isNotEmpty) ...[
              const SectionHeader('Top artists'),
              for (final (name, count, ms) in artists.take(10))
                ListTile(dense: true, title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)), trailing: Text('$count plays · ${formatDuration(Duration(milliseconds: ms))}')),
            ],
            const SectionHeader('Most played'),
            if (top.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Play some music to see stats.')),
            for (var i = 0; i < top.length; i++)
              TrackTile(track: top[i].$1, index: i + 1, trailing: Padding(padding: const EdgeInsets.only(right: 12), child: Text('${top[i].$2}×', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900))), onTap: () => pc.playTracks([for (final t in top) t.$1], start: i, queueName: 'Most played')),
          ]),
          ListView.builder(
            itemCount: history.length,
            itemBuilder: (_, i) {
              final (t, at) = history[i];
              final d = DateTime.fromMillisecondsSinceEpoch(at);
              return TrackTile(track: t, trailing: Padding(padding: const EdgeInsets.only(right: 12), child: Text('${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 11))), onTap: () => pc.playTracks([t]));
            },
          ),
        ]),
      ),
    );
  }
}
