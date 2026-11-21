import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/nok_theme.dart';

/// Accurate HSV/HSB colour picker: hue/saturation wheel, value + alpha,
/// precise H/S/V/A sliders with numeric fields and fine-step buttons,
/// hex input and swatches. Original NOKBOX widget.
class HsvColorPicker extends StatefulWidget {
  const HsvColorPicker({
    super.key,
    required this.initial,
    required this.onChanged,
    this.showAlpha = true,
    this.swatches = const [],
  });

  final Color initial;
  final ValueChanged<Color> onChanged;
  final bool showAlpha;
  final List<Color> swatches;

  @override
  State<HsvColorPicker> createState() => _HsvColorPickerState();
}

class _HsvColorPickerState extends State<HsvColorPicker> {
  late HSVColor _hsv;
  late final TextEditingController _hex;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hex = TextEditingController(text: _hexText);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  String get _hexText => colorToHex(_hsv.toColor(), withAlpha: widget.showAlpha).substring(1);

  void _set(HSVColor c, {bool updateHex = true}) {
    setState(() => _hsv = c);
    if (updateHex) {
      final t = _hexText;
      _hex.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
    }
    widget.onChanged(c.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _hsv.toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: _HueSatWheel(hsv: _hsv, onChanged: (c) => _set(c)),
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              height: 220,
              child: _VerticalValueBar(hsv: _hsv, onChanged: (c) => _set(c)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(children: [
          _Swatch(color: widget.initial, label: 'Old', onTap: () => _set(HSVColor.fromColor(widget.initial))),
          const SizedBox(width: 8),
          _Swatch(color: color, label: 'New'),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: _hex,
              decoration: InputDecoration(prefixText: '#', labelText: widget.showAlpha ? 'Hex (AARRGGBB)' : 'Hex (RRGGBB)', isDense: true),
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, letterSpacing: 1.2),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')), LengthLimitingTextInputFormatter(8)],
              onChanged: (v) {
                final c = hexToColor(v);
                if (c != null && (v.length == 6 || v.length == 8)) _set(HSVColor.fromColor(c), updateHex: false);
              },
            ),
          ),
          IconButton(
            tooltip: 'Copy hex',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => Clipboard.setData(ClipboardData(text: '#$_hexText')),
          ),
        ]),
        const SizedBox(height: 12),
        _ChannelSlider(
          label: 'H',
          unit: '°',
          value: _hsv.hue,
          max: 360,
          gradient: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()],
          onChanged: (v) => _set(_hsv.withHue(v.clamp(0, 359.999))),
        ),
        _ChannelSlider(
          label: 'S',
          unit: '%',
          value: _hsv.saturation * 100,
          max: 100,
          gradient: [_hsv.withSaturation(0).withAlpha(1).toColor(), _hsv.withSaturation(1).withAlpha(1).toColor()],
          onChanged: (v) => _set(_hsv.withSaturation(v / 100)),
        ),
        _ChannelSlider(
          label: 'V',
          unit: '%',
          value: _hsv.value * 100,
          max: 100,
          gradient: [Colors.black, _hsv.withValue(1).withAlpha(1).toColor()],
          onChanged: (v) => _set(_hsv.withValue(v / 100)),
        ),
        if (widget.showAlpha)
          _ChannelSlider(
            label: 'A',
            unit: '%',
            value: _hsv.alpha * 100,
            max: 100,
            checker: true,
            gradient: [_hsv.withAlpha(0).toColor(), _hsv.withAlpha(1).toColor()],
            onChanged: (v) => _set(_hsv.withAlpha(v / 100)),
          ),
        if (widget.swatches.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Swatches', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7), fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in widget.swatches)
                GestureDetector(
                  onTap: () => _set(HSVColor.fromColor(s)),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: s,
                      shape: BoxShape.circle,
                      border: Border.all(color: s.toARGB32() == color.toARGB32() ? cs.onSurface : Colors.white24, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.label, this.onTap});
  final Color color;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CustomPaint(
            painter: _CheckerPainter(radius: 10),
            child: Container(width: 44, height: 32, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24))),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10)),
        ]),
      );
}

/// Hue = angle, saturation = distance from centre. Value is shown as darkening.
class _HueSatWheel extends StatelessWidget {
  const _HueSatWheel({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _handle(Offset local, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;
    final d = local - c;
    var angle = math.atan2(d.dy, d.dx) * 180 / math.pi;
    if (angle < 0) angle += 360;
    final sat = (d.distance / r).clamp(0.0, 1.0);
    HapticFeedback.selectionClick();
    onChanged(hsv.withHue(angle % 360).withSaturation(sat));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      return GestureDetector(
        onPanDown: (d) => _handle(d.localPosition, size),
        onPanUpdate: (d) => _handle(d.localPosition, size),
        child: CustomPaint(size: size, painter: _WheelPainter(hsv)),
      );
    });
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final hues = [for (var h = 0; h <= 360; h += 15) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()];
    canvas.drawCircle(c, r, Paint()..shader = SweepGradient(colors: hues).createShader(rect));
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = const RadialGradient(colors: [Colors.white, Color(0x00FFFFFF)]).createShader(rect),
    );
    canvas.drawCircle(c, r, Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value));
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white24);
    // crosshair rings
    for (final f in [0.25, 0.5, 0.75]) {
      canvas.drawCircle(c, r * f, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = Colors.white10);
    }
    final a = hsv.hue * math.pi / 180;
    final p = c + Offset(math.cos(a), math.sin(a)) * (hsv.saturation * r);
    canvas.drawCircle(p, 13, Paint()..color = Colors.black54);
    canvas.drawCircle(p, 11, Paint()..color = hsv.withAlpha(1).toColor());
    canvas.drawCircle(p, 11, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hsv != hsv;
}

class _VerticalValueBar extends StatelessWidget {
  const _VerticalValueBar({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.maxHeight;
      void handle(Offset p) => onChanged(hsv.withValue((1 - p.dy / h).clamp(0.0, 1.0)));
      return GestureDetector(
        onPanDown: (d) => handle(d.localPosition),
        onPanUpdate: (d) => handle(d.localPosition),
        child: CustomPaint(
          size: Size(34, h),
          painter: _VBarPainter(hsv),
        ),
      );
    });
  }
}

class _VBarPainter extends CustomPainter {
  _VBarPainter(this.hsv);
  final HSVColor hsv;
  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(17));
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [hsv.withValue(1).withAlpha(1).toColor(), Colors.black],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white24);
    final y = (1 - hsv.value) * size.height;
    final thumb = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(size.width / 2, y.clamp(6, size.height - 6)), width: size.width + 6, height: 10), const Radius.circular(5));
    canvas.drawRRect(thumb, Paint()..color = Colors.white);
    canvas.drawRRect(thumb, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black54);
  }

  @override
  bool shouldRepaint(_VBarPainter old) => old.hsv != hsv;
}

class _ChannelSlider extends StatelessWidget {
  const _ChannelSlider({
    required this.label,
    required this.unit,
    required this.value,
    required this.max,
    required this.gradient,
    required this.onChanged,
    this.checker = false,
  });

  final String label;
  final String unit;
  final double value;
  final double max;
  final List<Color> gradient;
  final ValueChanged<double> onChanged;
  final bool checker;

  @override
  Widget build(BuildContext context) {
    final step = max == 360 ? 1.0 : 0.5;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 18, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900))),
        _Nudge(icon: Icons.remove, onTap: () => onChanged((value - step).clamp(0, max))),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            void handle(double dx) => onChanged((dx / w * max).clamp(0, max));
            return GestureDetector(
              onHorizontalDragDown: (d) => handle(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => handle(d.localPosition.dx),
              child: CustomPaint(
                size: Size(w, 28),
                painter: _TrackPainter(gradient, value / max, checker),
              ),
            );
          }),
        ),
        _Nudge(icon: Icons.add, onTap: () => onChanged((value + step).clamp(0, max))),
        SizedBox(
          width: 58,
          child: Text(
            '${value.toStringAsFixed(max == 360 ? 0 : 1)}$unit',
            textAlign: TextAlign.right,
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }
}

class _Nudge extends StatelessWidget {
  const _Nudge({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 16)),
      );
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.colors, this.t, this.checker);
  final List<Color> colors;
  final double t;
  final bool checker;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Rect.fromLTWH(0, size.height / 2 - 8, size.width, 16);
    final rr = RRect.fromRectAndRadius(track, const Radius.circular(8));
    if (checker) {
      canvas.save();
      canvas.clipRRect(rr);
      _paintChecker(canvas, track, 6);
      canvas.restore();
    }
    canvas.drawRRect(rr, Paint()..shader = LinearGradient(colors: colors).createShader(track));
    canvas.drawRRect(rr, Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white24);
    final x = (t.clamp(0.0, 1.0)) * size.width;
    final c = Offset(x.clamp(10, size.width - 10), size.height / 2);
    canvas.drawCircle(c, 12, Paint()..color = Colors.black45);
    canvas.drawCircle(c, 10, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.t != t || old.colors != colors;
}

void _paintChecker(Canvas canvas, Rect r, double s) {
  final p1 = Paint()..color = const Color(0xFF9E9E9E);
  final p2 = Paint()..color = const Color(0xFFE0E0E0);
  for (var y = r.top; y < r.bottom; y += s) {
    for (var x = r.left; x < r.right; x += s) {
      final even = (((x - r.left) / s).floor() + ((y - r.top) / s).floor()) % 2 == 0;
      canvas.drawRect(Rect.fromLTWH(x, y, s, s), even ? p1 : p2);
    }
  }
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter({this.radius = 0});
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
    _paintChecker(canvas, r, 6);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Opens the picker in a bottom sheet and returns the chosen colour.
Future<Color?> showHsvColorPicker(BuildContext context, {required Color initial, String title = 'Pick a colour', bool showAlpha = true}) {
  var current = initial;
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 14),
            HsvColorPicker(
              initial: initial,
              showAlpha: showAlpha,
              swatches: [for (final p in NokThemeSpec.presets) p.accent, Colors.white, const Color(0xFF8A8A8A)],
              onChanged: (c) => current = c,
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx, current), child: const Text('Apply'))),
            ]),
          ]),
        ),
      ),
    ),
  );
}
