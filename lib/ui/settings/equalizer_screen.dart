import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../audio/eq.dart';
import '../../audio/equalizer_controller.dart';
import '../widgets/common.dart';

/// Opens the equalizer as a bottom sheet over the player. Playback is not
/// touched — the sheet is purely UI, so nothing pauses or restarts while
/// it is open.
Future<void> showEqBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.92,
      child: const EqualizerScreen(),
    ),
  );
}

/// Equalizer hub: curve view, 10-band graphic sliders, parametric band
/// editor, preamp with auto-headroom, bass boost, presets, AutoEQ import,
/// per-output profiles. Same chain on local files and streams.
class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerController>();
    final cs = Theme.of(context).colorScheme;
    final p = eq.profile;
    final isGraphic = p.bands.length == EqProfile.graphicFreqs.length && p.bands.every((b) => b.type == EqFilterType.peak);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Equalizer'),
          actions: [
            Switch(value: eq.enabled, onChanged: eq.setEnabled),
            PopupMenuButton<String>(
              onSelected: (v) => _menu(context, eq, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'save', child: Text('Save as preset…')),
                PopupMenuItem(value: 'autoeq', child: Text('Import AutoEQ (ParametricEQ.txt / GraphicEQ.txt)')),
                PopupMenuItem(value: 'paste', child: Text('Paste AutoEQ / NOKBOX EQ from clipboard')),
                PopupMenuItem(value: 'export', child: Text('Copy current EQ as JSON')),
                PopupMenuItem(value: 'reset', child: Text('Reset to flat')),
              ],
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Graphic'), Tab(text: 'Parametric'), Tab(text: 'FX')]),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              height: 140,
              decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(18)),
              child: CustomPaint(painter: _CurvePainter(p, cs.primary, cs.onSurface, eq.enabled), size: Size.infinite),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
              for (final pr in eq.allProfiles)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    label: Text(pr.name),
                    selected: pr.name == p.name,
                    onSelected: (_) => eq.select(pr),
                    onDeleted: pr.builtIn ? null : () => eq.deleteCustom(pr.name),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: TabBarView(children: [
              isGraphic ? _GraphicBands(eq: eq) : _NonGraphicNotice(eq: eq),
              _ParametricList(eq: eq),
              _FxControls(eq: eq),
            ]),
          ),
          _MasterControls(eq: eq),
        ]),
      ),
    );
  }

  Future<void> _menu(BuildContext context, EqualizerController eq, String v) async {
    switch (v) {
      case 'save':
        final n = await promptText(context, title: 'Save preset', initial: eq.profile.name);
        if (n != null && n.trim().isNotEmpty) eq.saveAs(n.trim());
      case 'autoeq':
        final r = await FilePicker.pickFiles(type: FileType.any);
        final f = r.firstOrNull;
        if (f == null) return;
        final text = await f.xFile.readAsString();
        try {
          final name = f.name.replaceAll(RegExp(r'\s*(Parametric|Graphic)EQ\.txt$'), '');
          eq.importAutoEq(text, name: 'AutoEQ · $name', attribution: 'AutoEQ (MIT, github.com/jaakkopasanen/AutoEq) — measurement by its original source');
          if (context.mounted) snack(context, 'Imported $name');
        } catch (e) {
          if (context.mounted) snack(context, 'Not an AutoEQ file: $e');
        }
      case 'paste':
        final d = await Clipboard.getData('text/plain');
        final text = d?.text ?? '';
        try {
          if (text.trimLeft().startsWith('{')) {
            eq.importJson(text);
          } else {
            eq.importAutoEq(text, name: 'AutoEQ · pasted');
          }
          if (context.mounted) snack(context, 'EQ imported');
        } catch (e) {
          if (context.mounted) snack(context, 'Could not import: $e');
        }
      case 'export':
        await Clipboard.setData(ClipboardData(text: eq.profile.encode()));
        if (context.mounted) snack(context, 'Copied EQ JSON');
      case 'reset':
        eq.reset();
    }
  }
}

String _fmtFreq(double f) => f >= 1000 ? '${(f / 1000).toStringAsFixed(f % 1000 == 0 ? 0 : 1)}k' : f.toStringAsFixed(0);

class _GraphicBands extends StatelessWidget {
  const _GraphicBands({required this.eq});
  final EqualizerController eq;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        for (var i = 0; i < eq.profile.bands.length; i++)
          Expanded(
            child: Column(children: [
              Text('${eq.profile.bands[i].gainDb >= 0 ? '+' : ''}${eq.profile.bands[i].gainDb.toStringAsFixed(1)}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: cs.primary)),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(trackHeight: 6, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9)),
                    child: Slider(value: eq.profile.bands[i].gainDb.clamp(-12, 12), min: -12, max: 12, divisions: 48, onChanged: (v) => eq.setBandGain(i, v)),
                  ),
                ),
              ),
              Text(_fmtFreq(eq.profile.bands[i].freq), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }
}

class _NonGraphicNotice extends StatelessWidget {
  const _NonGraphicNotice({required this.eq});
  final EqualizerController eq;
  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.tune_rounded,
        title: 'Parametric profile active',
        message: '${eq.profile.name} uses ${eq.profile.bands.length} parametric filters${eq.profile.source != null ? '\n${eq.profile.source}' : ''}. Edit it in the Parametric tab.',
      );
}

class _ParametricList extends StatelessWidget {
  const _ParametricList({required this.eq});
  final EqualizerController eq;
  @override
  Widget build(BuildContext context) {
    final bands = eq.profile.bands;
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
      for (var i = 0; i < bands.length; i++) _BandEditor(index: i, band: bands[i], eq: eq),
      TextButton.icon(onPressed: () => eq.addBand(const EqBand(freq: 1000, gainDb: 0, q: 1)), icon: const Icon(Icons.add_rounded), label: const Text('Add filter')),
      if (eq.profile.source != null) Padding(padding: const EdgeInsets.all(8), child: Text(eq.profile.source!, style: const TextStyle(fontSize: 11))),
    ]);
  }
}

class _FxControls extends StatelessWidget {
  const _FxControls({required this.eq});
  final EqualizerController eq;
  @override
  Widget build(BuildContext context) {
    final p = eq.profile;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
      const Text('Effects are off at 0 — your EQ sound does not change until you move a slider.', style: TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      _fxRow('Reverb', p.reverbAmount, eq.setReverbAmount, valueLabel: '${(p.reverbAmount * 100).round()}%'),
      _fxRow('Room size', p.reverbRoom, eq.setReverbRoom, valueLabel: '${(p.reverbRoom * 100).round()}%'),
      _fxRow('Damping', p.reverbDamping, eq.setReverbDamping, valueLabel: '${(p.reverbDamping * 100).round()}%'),
      _fxRow('Wet', p.reverbWet, eq.setReverbWet, valueLabel: '${(p.reverbWet * 100).round()}%'),
      _fxRow('Stereo width', p.stereoWidth, eq.setStereoWidth, min: 0, max: 2, valueLabel: '${(p.stereoWidth * 100).round()}%'),
      _fxRow('Virtualizer', p.virtualizer, eq.setVirtualizer, valueLabel: '${(p.virtualizer * 100).round()}%'),
      _fxRow('3D', p.threeD, eq.setThreeD, valueLabel: '${(p.threeD * 100).round()}%'),
      const SizedBox(height: 8),
      TextButton.icon(onPressed: eq.resetFx, icon: const Icon(Icons.restart_alt_rounded), label: const Text('Reset effects')),
    ]);
  }
}

Widget _fxRow(String label, double value, ValueChanged<double> onChanged, {double min = 0, double max = 1, required String valueLabel}) {
  return Row(children: [
    SizedBox(width: 96, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
    Expanded(
      child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: ((max - min) * 20).round(), onChanged: onChanged),
    ),
    SizedBox(width: 44, child: Text(valueLabel, textAlign: TextAlign.right)),
  ]);
}

class _BandEditor extends StatelessWidget {
  const _BandEditor({required this.index, required this.band, required this.eq});
  final int index;
  final EqBand band;
  final EqualizerController eq;
  @override
  Widget build(BuildContext context) {
    final logF = math.log(band.freq) / math.ln10;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Column(children: [
          Row(children: [
            Checkbox(value: band.enabled, onChanged: (v) => eq.updateBand(index, band.copyWith(enabled: v))),
            DropdownButton<EqFilterType>(
              value: band.type,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: EqFilterType.peak, child: Text('Peak')),
                DropdownMenuItem(value: EqFilterType.lowShelf, child: Text('Low shelf')),
                DropdownMenuItem(value: EqFilterType.highShelf, child: Text('High shelf')),
              ],
              onChanged: (t) => eq.updateBand(index, band.copyWith(type: t)),
            ),
            const Spacer(),
            Text('${_fmtFreq(band.freq)}Hz  ${band.gainDb >= 0 ? '+' : ''}${band.gainDb.toStringAsFixed(1)}dB  Q${band.q.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => eq.removeBand(index)),
          ]),
          _row('Freq', Slider(value: logF.clamp(math.log(20) / math.ln10, math.log(20000) / math.ln10), min: math.log(20) / math.ln10, max: math.log(20000) / math.ln10, onChanged: (v) => eq.updateBand(index, band.copyWith(freq: math.pow(10, v).toDouble().roundToDouble())))),
          _row('Gain', Slider(value: band.gainDb.clamp(-15, 15), min: -15, max: 15, divisions: 120, onChanged: (v) => eq.updateBand(index, band.copyWith(gainDb: v)))),
          _row('Q', Slider(value: band.q.clamp(0.1, 10), min: 0.1, max: 10, onChanged: (v) => eq.updateBand(index, band.copyWith(q: v)))),
        ]),
      ),
    );
  }

  Widget _row(String l, Widget s) => Row(children: [SizedBox(width: 40, child: Text(l, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))), Expanded(child: s)]);
}

class _MasterControls extends StatelessWidget {
  const _MasterControls({required this.eq});
  final EqualizerController eq;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const SizedBox(width: 80, child: Text('Bass boost', style: TextStyle(fontWeight: FontWeight.w800))),
            Expanded(child: Slider(value: eq.profile.bassBoostDb.clamp(0, 12), max: 12, divisions: 24, onChanged: eq.setBassBoost)),
            SizedBox(width: 50, child: Text('+${eq.profile.bassBoostDb.toStringAsFixed(1)}', textAlign: TextAlign.right)),
          ]),
          Row(children: [
            const SizedBox(width: 80, child: Text('Preamp', style: TextStyle(fontWeight: FontWeight.w800))),
            Expanded(child: Slider(value: eq.profile.preampDb.clamp(-15, 6), min: -15, max: 6, divisions: 42, onChanged: eq.autoPreamp ? null : eq.setPreamp)),
            SizedBox(width: 50, child: Text(eq.effectivePreamp.toStringAsFixed(1), textAlign: TextAlign.right)),
          ]),
          Row(children: [
            Expanded(child: Text('Auto headroom (prevents clipping)', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7)))),
            Switch(value: eq.autoPreamp, onChanged: eq.setAutoPreamp),
          ]),
          Row(children: [
            Icon(Icons.headphones_rounded, size: 16, color: cs.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Expanded(child: Text('Output: ${eq.currentOutput} · profile saved per output', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7)))),
            Text('Applies to local + streams', style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.p, this.accent, this.fg, this.enabled);
  final EqProfile p;
  final Color accent;
  final Color fg;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = fg.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (final db in [-12, -6, 0, 6, 12]) {
      final y = size.height / 2 - db / 15 * size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid..color = fg.withValues(alpha: db == 0 ? 0.2 : 0.07));
    }
    for (final f in [100.0, 1000.0, 10000.0]) {
      final x = (math.log(f / 20) / math.log(1000)) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final path = Path();
    const n = 120;
    for (var i = 0; i <= n; i++) {
      final f = 20 * math.pow(1000, i / n).toDouble();
      final db = p.responseAt(f);
      final x = i / n * size.width;
      final y = (size.height / 2 - db / 15 * size.height / 2).clamp(2.0, size.height - 2);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(fill, Paint()..color = accent.withValues(alpha: enabled ? 0.18 : 0.05));
    canvas.drawPath(path, Paint()
      ..color = enabled ? accent : fg.withValues(alpha: 0.3)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_CurvePainter o) => true;
}
