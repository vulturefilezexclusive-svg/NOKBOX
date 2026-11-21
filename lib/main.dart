import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:audio_session/audio_session.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'app_globals.dart';
import 'core/diagnostics.dart';
import 'core/services.dart';
import 'ui/app.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Diag.init((await getApplicationSupportDirectory()).path, info: 'NOKBOX 0.2.1');
    } catch (_) {}
    Diag.installHooks();
    MediaKit.ensureInitialized();
    try {
      // Playback category: keeps audio going when backgrounded / locked.
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);
    } catch (e) {
      Diag.warn('audio', 'session: $e');
    }
    nok = await Services.init();
    Diag.info('app', 'services ready');
    runApp(const NokboxApp());
  }, (e, s) => Diag.error('zone', '$e', stack: s));
}
