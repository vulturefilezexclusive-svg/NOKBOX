import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../audio/playback_controller.dart';
import '../../core/settings.dart';
import '../../lyrics/lyrics_controller.dart';

/// Synced lyrics: auto-scrolls, highlights active line (word-level when
/// available), tap a line to seek, offset nudging, refetch and editor.
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, this.fullscreen = false});
  final bool fullscreen;
  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _scroll = ScrollController();
  int _lastIndex = -2;
  static const _lineH = 56.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lc = context.watch<LyricsController>();
    final pc = context.watch<PlaybackController>();
    final s = context.watch<SettingsStore>();
    final cs = Theme.of(context).colorScheme;
    final l = lc.lyrics;
    Widget body;
    if (lc.loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (l == null || l.isEmpty) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lyrics_outlined, size: 48, color: cs.primary),
          const SizedBox(height: 10),
          const Text('No lyrics found', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(onPressed: () => lc.load(pc.current, force: true), icon: const Icon(Icons.refresh_rounded), label: const Text('Search LRCLIB')),
            OutlinedButton.icon(onPressed: () => _edit(context, lc, pc), icon: const Icon(Icons.edit_rounded), label: const Text('Add')),
          ]),
        ]),
      );
    } else if (!l.synced) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(l.plain ?? '', textAlign: TextAlign.center, style: TextStyle(fontSize: 18 * s.lyricsFontScale, height: 1.6, fontWeight: FontWeight.w700)),
      );
    } else {
      final idx = l.indexAt(pc.position + lc.userOffset);
      if (idx != _lastIndex) {
        _lastIndex = idx;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients && idx >= 0) {
            final target = (idx * _lineH - _scroll.position.viewportDimension / 2 + _lineH).clamp(0.0, _scroll.position.maxScrollExtent);
            _scroll.animateTo(target, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
          }
        });
      }
      body = ShaderMask(
        shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent], stops: [0, 0.12, 0.88, 1]).createShader(r),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(vertical: 120),
          itemCount: l.lines.length,
          itemExtent: _lineH,
          itemBuilder: (context, i) {
            final line = l.lines[i];
            final active = i == idx;
            final past = i < idx;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => pc.seek(line.time - l.offset),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: (active ? 24 : 19) * s.lyricsFontScale,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    color: active ? cs.onSurface : cs.onSurface.withValues(alpha: past ? 0.35 : 0.5),
                    shadows: active ? [Shadow(color: cs.primary.withValues(alpha: 0.8), blurRadius: 18)] : null,
                  ),
                  child: Text(line.text.isEmpty ? '♪' : line.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
            );
          },
        ),
      );
    }
    return Column(children: [
      Expanded(child: body),
      Row(children: [
        Text(l?.source.isNotEmpty == true ? 'Lyrics · ${l!.source}' : '', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
        const Spacer(),
        if (l?.synced == true) ...[
          IconButton(tooltip: 'Lyrics earlier', icon: const Icon(Icons.fast_rewind_rounded, size: 18), onPressed: () => lc.nudgeOffset(-250)),
          Text('${lc.userOffset.inMilliseconds >= 0 ? '+' : ''}${(lc.userOffset.inMilliseconds / 1000).toStringAsFixed(2)}s', style: const TextStyle(fontSize: 11)),
          IconButton(tooltip: 'Lyrics later', icon: const Icon(Icons.fast_forward_rounded, size: 18), onPressed: () => lc.nudgeOffset(250)),
        ],
        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_note_rounded, size: 20), onPressed: () => _edit(context, lc, pc)),
        IconButton(tooltip: 'Refetch', icon: const Icon(Icons.refresh_rounded, size: 20), onPressed: () => lc.load(pc.current, force: true)),
      ]),
    ]);
  }

  Future<void> _edit(BuildContext context, LyricsController lc, PlaybackController pc) async {
    final t = pc.current;
    if (t == null) return;
    final c = TextEditingController(text: lc.lyrics?.synced == true ? lc.lyrics!.lines.map((e) => '[${_ts(e.time)}]${e.text}').join('\n') : (lc.lyrics?.plain ?? ''));
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Lyrics editor (LRC or plain)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SizedBox(height: 320, child: TextField(controller: c, maxLines: null, expands: true, style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () {
                final pos = pc.position;
                final sel = c.selection.baseOffset < 0 ? c.text.length : c.selection.baseOffset;
                final lineStart = c.text.lastIndexOf('\n', sel > 0 ? sel - 1 : 0) + 1;
                c.text = '${c.text.substring(0, lineStart)}[${_ts(pos)}]${c.text.substring(lineStart)}';
              },
              icon: const Icon(Icons.timer_rounded),
              label: const Text('Stamp line'),
            ),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
          ]),
        ]),
      ),
    );
    if (res != null) lc.saveEdited(t, res);
  }

  static String _ts(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}.${(d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0')}';
}
