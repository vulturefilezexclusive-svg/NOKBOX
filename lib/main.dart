import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

import 'app_globals.dart';
import 'core/services.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  nok = await Services.init();
  runApp(const NokboxApp());
}
