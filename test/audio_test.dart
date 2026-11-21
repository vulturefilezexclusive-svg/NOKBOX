import 'package:flutter_test/flutter_test.dart';
import 'package:nokbox/audio/audio_backend.dart';
import 'package:nokbox/audio/eq.dart';
import 'package:nokbox/audio/equalizer_controller.dart';
import 'package:nokbox/audio/mpv_filters.dart';
import 'package:nokbox/data/database.dart';

/// The iOS/macOS libmpv that media_kit ships is built with a trimmed
/// libavfilter (`--disable-all --enable-filter=overlay --enable-filter=equalizer`),
/// so the reverb / stereo-width / virtualizer / 3D filters do not exist there.
/// A chain that mentions one is rejected — and mpv answers a rejected audio
/// filter chain with no sound at all. These tests pin the two safety nets that
/// keep playback audible: build an equalizer-only chain on request, and drop
/// the chain (rather than the audio) if it is refused.
void main() {
  test('equalizer-only chain never mentions filters the iOS engine lacks', () {
    final p = EqProfile.builtIns[1].copyWith(reverbAmount: 0.6, stereoWidth: 1.4);
    final full = const MpvEqBuilder().build(p);
    expect(full, contains('aecho'));
    expect(full, contains('extrastereo'));
    final safe = const MpvEqBuilder().build(p, equalizerOnly: true);
    expect(safe, startsWith('@nokeq:lavfi=['));
    expect(safe, contains('equalizer='));
    expect(safe, isNot(contains('aecho')));
    expect(safe, isNot(contains('extrastereo')));
  });

  test('the equalizer falls back instead of leaving playback silent', () async {
    final db = NokDatabase.memory();
    final backend = FakeAudioBackend()..unsupportedFilters.add('aecho');
    final eq = EqualizerController(db: db, backend: backend);
    eq.select(EqProfile.builtIns[1]);
    eq.setReverbAmount(0.6);
    await eq.apply();
    expect(backend.lastFilter, contains('equalizer='));
    expect(backend.lastFilter, isNot(contains('aecho')));
    expect(eq.effectsUnavailable, isTrue);
    db.close();
  });

  test('a filter that fails during playback is dropped, not the sound', () async {
    final db = NokDatabase.memory();
    final backend = FakeAudioBackend();
    final eq = EqualizerController(db: db, backend: backend);
    eq.select(EqProfile.builtIns[1]);
    eq.setReverbAmount(0.5);
    await eq.apply();
    expect(backend.lastFilter, contains('aecho'));
    // mpv accepted the chain but could not build it once audio started.
    backend.failFilter();
    await pumpEventQueue();
    expect(eq.effectsUnavailable, isTrue);
    expect(backend.lastFilter, contains('equalizer='));
    expect(backend.lastFilter, isNot(contains('aecho')));
    db.close();
  });
}
