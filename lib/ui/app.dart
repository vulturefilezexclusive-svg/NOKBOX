import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_globals.dart';
import '../core/theme/theme_controller.dart';
import 'root_shell.dart';

class NokboxApp extends StatelessWidget {
  const NokboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: nok.settings),
        ChangeNotifierProvider.value(value: nok.theme),
        ChangeNotifierProvider.value(value: nok.library),
        ChangeNotifierProvider.value(value: nok.registry),
        ChangeNotifierProvider.value(value: nok.eq),
        ChangeNotifierProvider.value(value: nok.playback),
        ChangeNotifierProvider.value(value: nok.lyrics),
        ChangeNotifierProvider.value(value: nok.downloads),
        ChangeNotifierProvider.value(value: nok.sponsorBlock),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          title: 'NOKBOX',
          debugShowCheckedModeBanner: false,
          theme: theme.theme,
          home: const RootShell(),
        ),
      ),
    );
  }
}
