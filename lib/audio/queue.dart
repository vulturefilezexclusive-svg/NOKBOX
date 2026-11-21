import 'dart:convert';
import 'dart:math';

import '../data/models.dart';

enum RepeatMode { off, all, one }

/// One live queue. Each remembers its own position so users can swipe
/// between up to [QueueSet.maxQueues] queues.
class PlayQueue {
  PlayQueue({required this.id, required this.name, List<Track>? items, this.index = 0, this.positionMs = 0, this.repeat = RepeatMode.off, this.shuffled = false})
      : items = items ?? [];

  final String id;
  String name;
  final List<Track> items;
  int index;
  int positionMs;
  RepeatMode repeat;
  bool shuffled;

  /// Original order before shuffle (ids).
  List<String>? _unshuffled;

  /// "Insert after latest inserted" pointer for Play next.
  int _insertCursor = -1;

  Track? get current => (index >= 0 && index < items.length) ? items[index] : null;
  bool get isEmpty => items.isEmpty;
  int get remainingMs => items.skip(index + 1).fold(0, (a, t) => a + t.durationMs);

  void playNext(List<Track> tracks) {
    final at = (_insertCursor > index && _insertCursor <= items.length) ? _insertCursor : index + 1;
    items.insertAll(at.clamp(0, items.length), tracks);
    _insertCursor = at + tracks.length;
  }

  void add(List<Track> tracks) => items.addAll(tracks);

  void removeAt(int i) {
    if (i < 0 || i >= items.length) return;
    items.removeAt(i);
    if (i < index) index--;
    if (index >= items.length) index = items.length - 1;
  }

  void move(int from, int to) {
    if (from == to) return;
    final t = items.removeAt(from);
    items.insert(to, t);
    if (from == index) {
      index = to;
    } else if (from < index && to >= index) {
      index--;
    } else if (from > index && to <= index) {
      index++;
    }
  }

  void setShuffle(bool on, {Random? rng}) {
    if (on == shuffled) return;
    final cur = current;
    if (on) {
      _unshuffled = items.map((t) => t.id).toList();
      final rest = [...items]..removeWhere((t) => t == cur);
      rest.shuffle(rng ?? Random());
      items
        ..clear()
        ..addAll([if (cur != null) cur, ...rest]);
      index = 0;
    } else if (_unshuffled != null) {
      final byId = {for (final t in items) t.id: t};
      final restored = [for (final id in _unshuffled!) if (byId[id] != null) byId[id]!];
      for (final t in items) {
        if (!restored.contains(t)) restored.add(t);
      }
      items
        ..clear()
        ..addAll(restored);
      index = cur == null ? 0 : items.indexOf(cur);
    }
    shuffled = on;
  }

  /// Index after the current one honouring repeat mode; null = end.
  int? nextIndex({bool userInitiated = false}) {
    if (items.isEmpty) return null;
    if (repeat == RepeatMode.one && !userInitiated) return index;
    if (index + 1 < items.length) return index + 1;
    return repeat == RepeatMode.off ? null : 0;
  }

  int? previousIndex() {
    if (items.isEmpty) return null;
    if (index > 0) return index - 1;
    return repeat == RepeatMode.all ? items.length - 1 : 0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'index': index,
        'positionMs': positionMs,
        'repeat': repeat.name,
        'shuffled': shuffled,
        'items': [for (final t in items) t.toJson()],
      };

  factory PlayQueue.fromJson(Map<String, dynamic> j) => PlayQueue(
        id: j['id'] as String,
        name: j['name'] as String,
        index: (j['index'] as num?)?.toInt() ?? 0,
        positionMs: (j['positionMs'] as num?)?.toInt() ?? 0,
        repeat: RepeatMode.values.firstWhere((r) => r.name == j['repeat'], orElse: () => RepeatMode.off),
        shuffled: j['shuffled'] as bool? ?? false,
        items: [for (final t in (j['items'] as List? ?? const [])) Track.fromJson(Map<String, dynamic>.from(t as Map))],
      );
}

class QueueSet {
  QueueSet({List<PlayQueue>? queues, this.active = 0}) : queues = queues ?? [PlayQueue(id: 'q1', name: 'Queue 1')];
  static const maxQueues = 20;
  final List<PlayQueue> queues;
  int active;

  PlayQueue get current => queues[active.clamp(0, queues.length - 1)];

  PlayQueue create({String? name}) {
    if (queues.length >= maxQueues) {
      // Recycle the oldest non-active queue.
      queues.removeAt(active == 0 ? 1 : 0);
      if (active > 0) active--;
    }
    var n = queues.length + 1;
    while (queues.any((q) => q.name == 'Queue $n')) {
      n++;
    }
    final q = PlayQueue(id: 'q${DateTime.now().microsecondsSinceEpoch}', name: name ?? 'Queue $n');
    queues.add(q);
    return q;
  }

  void delete(int i) {
    if (queues.length == 1) {
      queues[0].items.clear();
      queues[0].index = 0;
      return;
    }
    queues.removeAt(i);
    if (active >= queues.length) active = queues.length - 1;
    if (i < active) active--;
  }

  String encode() => jsonEncode({'active': active, 'queues': [for (final q in queues) q.toJson()]});

  static QueueSet decode(String s) {
    final j = jsonDecode(s) as Map<String, dynamic>;
    final qs = [for (final q in (j['queues'] as List)) PlayQueue.fromJson(Map<String, dynamic>.from(q as Map))];
    return QueueSet(queues: qs.isEmpty ? null : qs, active: (j['active'] as num?)?.toInt() ?? 0);
  }
}
