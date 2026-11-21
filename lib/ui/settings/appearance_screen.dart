import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/nok_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../widgets/common.dart';
import '../widgets/hsv_color_picker.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tc = context.watch<ThemeController>();
    final s = context.watch<SettingsStore>();
    final spec = tc.spec;
    final cs = Theme.of(context).colorScheme;
    Widget colorRow(String label, Color c, ValueChanged<Color> onPick, {bool alpha = false}) => ListTile(
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(colorToHex(c), style: const TextStyle(fontFamily: 'monospace')),
          trailing: Container(width: 40, height: 40, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 2))),
          onTap: () async {
            final picked = await showHsvColorPicker(context, initial: c, title: label, showAlpha: alpha);
            if (picked != null) onPick(picked);
          },
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Theme & appearance')),
      body: ListView(children: [
        const SectionHeader('Presets'),
        SizedBox(
          height: 112,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final p in [...NokThemeSpec.presets, ...tc.saved])
              GestureDetector(
                onTap: () => tc.apply(p),
                onLongPress: NokThemeSpec.presets.contains(p) ? null : () => tc.deleteSaved(p.name),
                child: Container(
                  width: 92,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: p.background,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.name == spec.name ? cs.primary : Colors.white12, width: p.name == spec.name ? 3 : 1),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CircleAvatar(radius: 10, backgroundColor: p.accent),
                      const SizedBox(width: 4),
                      CircleAvatar(radius: 7, backgroundColor: p.secondary ?? p.accent),
                    ]),
                    const Spacer(),
                    Container(height: 6, width: 50, decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(height: 6),
                    Text(p.name, maxLines: 2, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.brightness == Brightness.dark ? Colors.white : Colors.black)),
                  ]),
                ),
              ),
          ]),
        ),
        const SectionHeader('Colors', subtitle: 'HSV/HSB wheel with precise H · S · V · A sliders'),
        colorRow('Accent', spec.accent, (c) => tc.update((s) => s.copyWith(accent: c, name: 'Custom'))),
        colorRow('Secondary', spec.secondary ?? spec.accent, (c) => tc.update((s) => s.copyWith(secondary: c, name: 'Custom'))),
        colorRow('Background', spec.background, (c) => tc.update((s) => s.copyWith(background: c, amoled: false, name: 'Custom'))),
        colorRow('Surfaces / cards', spec.surface, (c) => tc.update((s) => s.copyWith(surface: c, name: 'Custom')), alpha: true),
        SwitchListTile(
          title: const Text('AMOLED pure black', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('True #000000 background — saves battery on OLED'),
          value: spec.amoled,
          onChanged: (v) => tc.update((s) => s.copyWith(amoled: v)),
        ),
        SwitchListTile(
          title: const Text('Dynamic colors from album art', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Accent follows the artwork of what\'s playing'),
          value: spec.dynamicFromArt,
          onChanged: (v) => tc.update((s) => s.copyWith(dynamicFromArt: v)),
        ),
        SwitchListTile(
          title: const Text('Light mode', style: TextStyle(fontWeight: FontWeight.w700)),
          value: spec.brightness == Brightness.light,
          onChanged: (v) => tc.update((s) => s.copyWith(brightness: v ? Brightness.light : Brightness.dark, amoled: v ? false : s.amoled, background: v ? const Color(0xFFF6F6F6) : Colors.black, surface: v ? Colors.white : const Color(0xFF0E0E0E))),
        ),
        ListTile(
          title: const Text('Corner roundness', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Slider(value: spec.radius, min: 0, max: 30, divisions: 30, label: spec.radius.toStringAsFixed(0), onChanged: (v) => tc.update((s) => s.copyWith(radius: v))),
        ),
        const SectionHeader('Player'),
        SwitchListTile(title: const Text('Waveform seek bar'), subtitle: const Text('Off = plain seek bar'), value: s.waveformSeekbar, onChanged: (v) => s.set('waveformSeekbar', v)),
        SwitchListTile(title: const Text('Volume slider on player'), value: s.showVolumeOnPlayer, onChanged: (v) => s.set('showVolumeOnPlayer', v)),
        SwitchListTile(title: const Text('Battery saver'), subtitle: const Text('Turns off blur, waveform & heavy animations'), value: s.batterySaver, onChanged: (v) => s.set('batterySaver', v)),
        SwitchListTile(title: const Text('Simple mode'), subtitle: const Text('Fewer buttons, cleaner screens'), value: s.simpleMode, onChanged: (v) => s.set('simpleMode', v)),
        const SectionHeader('Save & share themes'),
        ListTile(
          leading: const Icon(Icons.save_rounded),
          title: const Text('Save current theme'),
          onTap: () async {
            final n = await promptText(context, title: 'Theme name', initial: spec.name == 'Custom' ? '' : spec.name);
            if (n != null && n.trim().isNotEmpty) await tc.saveCurrentAs(n.trim());
          },
        ),
        ListTile(
          leading: const Icon(Icons.ios_share_rounded),
          title: const Text('Export theme (copy JSON)'),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: tc.exportTheme()));
            if (context.mounted) snack(context, 'Theme copied — share it anywhere');
          },
        ),
        ListTile(
          leading: const Icon(Icons.content_paste_rounded),
          title: const Text('Import theme from clipboard'),
          onTap: () async {
            final d = await Clipboard.getData('text/plain');
            try {
              final t = await tc.importTheme(d?.text ?? '');
              if (context.mounted) snack(context, 'Imported ${t.name}');
            } catch (e) {
              if (context.mounted) snack(context, 'Invalid theme: $e');
            }
          },
        ),
        ListTile(leading: const Icon(Icons.restart_alt_rounded), title: const Text('Reset to NOKBOX OLED (black + red)'), onTap: tc.resetToStock),
        const SizedBox(height: 30),
      ]),
    );
  }
}
