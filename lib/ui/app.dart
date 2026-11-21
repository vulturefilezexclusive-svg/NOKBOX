import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_globals.dart';
import '../core/theme/theme_controller.dart';
import 'root_shell.dart';
import 'splash_screen.dart';

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
          home: const _SplashGate(),
        ),
      ),
    );
  }
}

/// Shows the animated splash on every cold start, then swaps to the
/// normal shell. Pure UI gate — it does not delay or touch audio init,
/// which already happened in main.dart before runApp.
class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(
        onDone: () {
          if (mounted) setState(() => _showSplash = false);
        },
      );
    }
    return const RootShell();
  }
}
