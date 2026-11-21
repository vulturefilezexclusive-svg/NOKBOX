import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../audio/playback_controller.dart';
import '../../library/library_controller.dart';
import '../../library/text_utils.dart';
import '../widgets/common.dart';

/// Multiple live queues: swipe between them (each remembers its spot),
/// reorder by drag, swipe a track to remove, save queue as playlist.
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});
  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  late final PageController _pages;

  @override
  void initState() {
    super.initState();
    _pages = PageController(initialPage: context.read<PlaybackController>().queues.active);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pc = context.watch<PlaybackController>();
    final cs = Theme.of(context).colorScheme;
    final qs = pc.queues.queues;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Queues'),
        actions: [
          IconButton(
            tooltip: 'New queue',
            icon: const Icon(Icons.add_rounded),
            onPressed: () {
              pc.newQueue();
              WidgetsBinding.instance.addPostFrameCallback((_) => _pages.animateToPage(pc.queues.queues.length - 1, duration: const Duration(milliseconds: 300), curve: Curves.easeOut));
            },
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: qs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ChoiceChip(
              avatar: i == pc.queues.active ? Icon(Icons.graphic_eq_rounded, size: 16, color: cs.primary) : null,
              label: Text('${qs[i].name} · ${qs[i].items.length}'),
              selected: i == pc.queues.active,
              onSelected: (_) => _pages.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
            ),
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: qs.length,
            itemBuilder: (context, qi) => _QueuePage(index: qi),
          ),
        ),
      ]),
    );
  }
}

class _QueuePage extends StatelessWidget {
  const _QueuePage({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final pc = context.watch<PlaybackController>();
    final cs = Theme.of(context).colorScheme;
    final q = pc.queues.queues[index];
    final active = index == pc.queues.active;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q.name, style: Theme.of(context).textTheme.titleLarge),
              Text('${q.items.length} tracks · ${formatDuration(Duration(milliseconds: q.items.fold(0, (a, t) => a + t.durationMs)))}${active ? ' · playing' : ' · paused at #${q.index + 1}'}',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
            ]),
          ),
          if (!active) FilledButton.tonalIcon(onPressed: () => pc.switchQueue(index), icon: const Icon(Icons.play_arrow_rounded), label: const Text('Resume')),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'rename':
                  final n = await promptText(context, title: 'Rename queue', initial: q.name);
                  if (n != null && n.trim().isNotEmpty) pc.renameQueue(index, n.trim());
                case 'save':
                  final n = await promptText(context, title: 'Save as playlist', initial: q.name);
                  if (n != null && n.trim().isNotEmpty && context.mounted) {
                    if (active) {
                      pc.saveQueueAsPlaylist(n.trim());
                    } else {
                      final lib = context.read<LibraryController>();
                      lib.addToPlaylist(lib.createPlaylist(n.trim()), q.items);
                    }
                    context.read<LibraryController>().loadFromDb();
                    if (context.mounted) snack(context, 'Saved "$n"');
                  }
                case 'clear':
                  if (active) {
                    pc.clearQueue();
                  } else {
                    pc.deleteQueue(index);
                  }
                case 'delete':
                  pc.deleteQueue(index);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'save', child: Text('Save as playlist')),
              PopupMenuItem(value: 'clear', child: Text('Clear')),
              PopupMenuItem(value: 'delete', child: Text('Delete queue')),
            ],
          ),
        ]),
      ),
      Expanded(
        child: q.items.isEmpty
            ? const EmptyState(icon: Icons.queue_music_rounded, title: 'Empty queue', message: 'Long-press any track → "Play in a new queue" or "Add to queue".')
            : ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: q.items.length,
                onReorder: (a, b) {
                  if (!active) return;
                  pc.move(a, b > a ? b - 1 : b);
                },
                itemBuilder: (context, i) {
                  final t = q.items[i];
                  return Dismissible(
                    key: ValueKey('${q.id}-${t.id}-$i'),
                    direction: active ? DismissDirection.endToStart : DismissDirection.none,
                    background: Container(color: cs.error.withValues(alpha: 0.6), alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete_rounded)),
                    onDismissed: (_) => pc.removeAt(i),
                    child: Container(
                      color: i == q.index ? cs.primary.withValues(alpha: 0.10) : null,
                      child: TrackTile(
                        track: t,
                        index: i + 1,
                        showArt: true,
                        dense: true,
                        onTap: () async {
                          if (!active) await pc.switchQueue(index);
                          await pc.jumpTo(i);
                        },
                        trailing: active ? ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.drag_handle_rounded))) : const SizedBox(width: 8),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
