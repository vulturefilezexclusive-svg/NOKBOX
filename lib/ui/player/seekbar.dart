import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../library/text_utils.dart';

/// Marker drawn on the seek bar (e.g. SponsorBlock segments, chapters).
class SeekMarker {
  const SeekMarker(this.start, this.end, this.color, {this.label = ''});
  final Duration start;
  final Duration end;
  final Color color;
  final String label;
}

/// Seek bar with two styles: stylized waveform (default) or plain line.
/// Supports drag-to-seek with a time bubble and segment markers.
class NokSeekBar extends StatefulWidget {
  const NokSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.waveform = true,
    this.seed = '',
    this.markers = const [],
    this.buffered,
  });
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final bool waveform;
  final String seed;
  final List<SeekMarker> markers;
  final Duration? buffered;

  @override
  State<NokSeekBar> createState() => _NokSeekBarState();
}

class _NokSeekBarState extends State<NokSeekBar> {
  double? _drag;
  List<double> _bars = const [];
  String _barsSeed = '\u0000';

  List<double> _barsFor(String seed) {
    if (seed == _barsSeed) return _bars;
    // Deterministic, music-shaped envelope per track (visual only; real
    // amplitude analysis is on the v1 list — see HANDOFF.md).
    final rng = math.Random(seed.hashCode);
    const n = 72;
    _bars = List.generate(n, (i) {
      final x = i / n;
      final env = 0.55 + 0.35 * math.sin(x * math.pi) + 0.1 * math.sin(x * 9 + rng.nextDouble());
      return (env * (0.45 + rng.nextDouble() * 0.55)).clamp(0.12, 1.0);
    });
    _barsSeed = seed;
    return _bars;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = widget.duration.inMilliseconds;
    final frac = _drag ?? (total > 0 ? (widget.position.inMilliseconds / total).clamp(0.0, 1.0) : 0.0);
    final shown = Duration(milliseconds: (frac * total).round());
    return Column(children: [
      LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        void update(double dx) => setState(() => _drag = (dx / w).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            HapticFeedback.selectionClick();
            update(d.localPosition.dx);
          },
          onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
          onHorizontalDragEnd: (_) {
            if (_drag != null && total > 0) widget.onSeek(Duration(milliseconds: (_drag! * total).round()));
            setState(() => _drag = null);
          },
          onTapUp: (d) {
            if (total > 0) widget.onSeek(Duration(milliseconds: ((d.localPosition.dx / w).clamp(0.0, 1.0) * total).round()));
          },
          child: SizedBox(
            height: widget.waveform ? 54 : 28,
            child: CustomPaint(
              size: Size(w, widget.waveform ? 54 : 28),
              painter: _SeekPainter(
                frac: frac,
                bars: widget.waveform ? _barsFor(widget.seed) : null,
                active: cs.primary,
                inactive: cs.onSurface.withValues(alpha: 0.18),
                markers: [
                  for (final m in widget.markers)
                    if (total > 0) (m.start.inMilliseconds / total, m.end.inMilliseconds / total, m.color),
                ],
                dragging: _drag != null,
              ),
            ),
          ),
        );
      }),
      const SizedBox(height: 4),
      Row(children: [
        Text(formatDuration(shown), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _drag != null ? cs.primary : cs.onSurface.withValues(alpha: 0.7), fontFeatures: const [FontFeature.tabularFigures()])),
        const Spacer(),
        Text(total > 0 ? '-${formatDuration(widget.duration - shown)}' : '--:--', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurface.withValues(alpha: 0.7), fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    ]);
  }
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({required this.frac, required this.bars, required this.active, required this.inactive, required this.markers, required this.dragging});
  final double frac;
  final List<double>? bars;
  final Color active;
  final Color inactive;
  final List<(double, double, Color)> markers;
  final bool dragging;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    if (bars != null) {
      final n = bars!.length;
      final bw = size.width / n;
      for (var i = 0; i < n; i++) {
        final x = i * bw + bw / 2;
        final h = bars![i] * (size.height - 8);
        final played = (i + 0.5) / n <= frac;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, mid), width: math.max(bw * 0.55, 1.5), height: h), const Radius.circular(2)),
          Paint()..color = played ? active : inactive,
        );
      }
    } else {
      final track = Paint()
        ..strokeWidth = dragging ? 6 : 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(0, mid), Offset(size.width, mid), track..color = inactive);
      canvas.drawLine(Offset(0, mid), Offset(size.width * frac, mid), track..color = active);
    }
    for (final (s, e, c) in markers) {
      final r = Rect.fromLTRB(size.width * s.clamp(0, 1), size.height - 4, size.width * e.clamp(0, 1), size.height);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)), Paint()..color = c);
    }
    final x = size.width * frac;
    canvas.drawCircle(Offset(x, mid), dragging ? 9 : 6, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(x, mid), dragging ? 5 : 3, Paint()..color = active);
  }

  @override
  bool shouldRepaint(_SeekPainter o) => o.frac != frac || o.bars != bars || o.active != active || o.markers.length != markers.length || o.dragging != dragging;
}
