import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Animated launch splash: the NOKBOX boombox art beats like a speaker
/// while the NOKBOX wordmark glows red, then hands off to the app.
///
/// Shows for 1.8 s on every cold start. It is pure UI — it does not touch
/// audio, playback, or the diagnostics hooks in main.dart (those all run
/// before [runApp]).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  /// One beat cycle = quick thump, settle, rest (~900 ms, so ~2 beats in
  /// the 1.8 s the splash is visible).
  late final AnimationController _beat;
  late final Animation<double> _scale;
  late final Animation<double> _glow;
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _beat = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.07).chain(CurveTween(curve: Curves.easeOut)), weight: 18),
      TweenSequenceItem(tween: Tween(begin: 1.07, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 32),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 50),
    ]).animate(_beat);
    _glow = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.35, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 18),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.35).chain(CurveTween(curve: Curves.easeInOut)), weight: 32),
      TweenSequenceItem(tween: ConstantTween<double>(0.35), weight: 50),
    ]).animate(_beat);
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted && !_done) {
        _done = true;
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final red = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _beat,
        builder: (context, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Beating speaker: the boombox brand art pulses on the beat.
              Transform.scale(
                scale: _scale.value,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: red.withValues(alpha: 0.45 * _glow.value),
                        blurRadius: 12 + 48 * _glow.value,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/branding/splash.png',
                      width: 260,
                      height: 260,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              // Glowing NOKBOX wordmark.
              Text(
                'NOKBOX',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                  color: red,
                  shadows: [
                    Shadow(color: red.withValues(alpha: 0.9 * _glow.value), blurRadius: 6 + 28 * _glow.value),
                    Shadow(color: red.withValues(alpha: 0.6 * _glow.value), blurRadius: 12),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'A MUZIK JUNKIE PARADISE',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w700,
                  color: red.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
