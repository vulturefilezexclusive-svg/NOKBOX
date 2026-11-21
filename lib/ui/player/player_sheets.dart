import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../audio/playback_controller.dart';
import '../../core/settings.dart';

String sleepLabel(PlaybackController pc) {
  switch (pc.sleepMode) {
    case SleepMode.minutes:
      final r = pc.sleepRemaining ?? Duration.zero;
      return '${r.inMinutes}:${r.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    case SleepMode.tracks:
      return '${pc.sleepTracksLeft} trk';
    case SleepMode.endOfTrack:
      return 'End';
    case SleepMode.off:
      return 'Sleep';
  }
}

Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      final pc = ctx.watch<PlaybackController>();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sleep timer', style: Theme.of(ctx).textTheme.titleLarge),
            if (pc.sleepMode != SleepMode.off)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('Active: ${sleepLabel(pc)} — fades out gently', style: TextStyle(color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.w700))),
            const SizedBox(height: 14),
            const Text('After minutes', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in [5, 10, 15, 20, 30, 45, 60, 90, 120])
                ActionChip(label: Text('$m min'), onPressed: () {
                  pc.setSleepMinutes(m);
                  Navigator.pop(ctx);
                }),
            ]),
            const SizedBox(height: 14),
            const Text('After tracks', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(label: const Text('End of this track'), onPressed: () {
                pc.setSleepEndOfTrack();
                Navigator.pop(ctx);
              }),
              for (final n in [2, 3, 5, 10])
                ActionChip(label: Text('$n tracks'), onPressed: () {
                  pc.setSleepTracks(n);
                  Navigator.pop(ctx);
                }),
            ]),
            const SizedBox(height: 16),
            if (pc.sleepMode != SleepMode.off)
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: pc.cancelSleep, icon: const Icon(Icons.close_rounded), label: const Text('Turn off'))),
          ]),
        ),
      );
    },
  );
}

Future<void> showSpeedSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      final pc = ctx.watch<PlaybackController>();
      final s = ctx.watch<SettingsStore>();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Speed & pitch', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('Speed ${s.speed.toStringAsFixed(2)}x', style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(value: s.speed, min: 0.5, max: 2.0, divisions: 30, onChanged: pc.setSpeed),
            Wrap(spacing: 8, children: [
              for (final v in [0.75, 0.85, 1.0, 1.15, 1.25, 1.5]) ChoiceChip(label: Text('${v}x'), selected: s.speed == v, onSelected: (_) => pc.setSpeed(v)),
            ]),
            const SizedBox(height: 14),
            Text('Pitch ${s.pitch.toStringAsFixed(2)}x', style: const TextStyle(fontWeight: FontWeight.w700)),
            Slider(value: s.pitch, min: 0.5, max: 1.5, divisions: 40, onChanged: pc.setPitch),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Normal'), selected: s.pitch == 1.0, onSelected: (_) => pc.setPitch(1.0)),
              ChoiceChip(label: const Text('432 Hz'), selected: (s.pitch - 0.9818).abs() < 0.001, onSelected: (_) => pc.setPitch(0.9818)),
              ChoiceChip(label: const Text('Slowed'), selected: s.pitch == 0.85, onSelected: (_) {
                pc.setPitch(0.85);
                pc.setSpeed(0.85);
              }),
              ChoiceChip(label: const Text('Sped up'), selected: s.pitch == 1.2, onSelected: (_) {
                pc.setPitch(1.2);
                pc.setSpeed(1.2);
              }),
            ]),
          ]),
        ),
      );
    },
  );
}
