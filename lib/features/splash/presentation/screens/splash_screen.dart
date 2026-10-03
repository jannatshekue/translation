import 'package:flutter/material.dart';

import '../../../../core/services/settings_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/app_routes.dart';

/// Shown once, right after the native OS launch screen hands off to Flutter.
///
/// The native launch screen can only show a still picture, so it shows this
/// screen's first frame exactly: [launchColor] with the icon tile dead centre
/// (see `flutter_native_splash` in pubspec.yaml and assets/splash). That makes
/// the hand-over invisible — it reads as one splash. From there the colour
/// eases into the full gradient, the tagline writes itself beneath the tile in
/// a flowing script (each letter easing in as the line moves along), and the
/// screen holds for a beat before landing on Home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// One word of the tagline and the colour it is drawn in.
class _Word {
  final String text;
  final Color color;

  const _Word(this.text, this.color);
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  /// Must match `color` in the flutter_native_splash config in pubspec.yaml.
  static const launchColor = Color(0xFF1C3273);

  // The tile is the same size as the one baked into the native launch screen
  // (assets/splash/splash_tile.png); both are centred on the screen.
  static const _tileSize = 132.0;
  static const _tileToTagline = 32.0;

  // Timeline, in milliseconds. The tile is already on screen at 0.
  static const _total = 4550;
  static const _gradientEnd = 700;
  static const _typeStart = 250;
  static const _typeEnd = 3150;

  /// How many letters wide the soft "front" of the writing is. A wider front
  /// makes the line flow in more gently; a narrow one looks like hard typing.
  static const _frontWidth = 3.0;

  // Trailing spaces belong to the word before them so offsets stay contiguous.
  static const _words = [
    _Word('Clear. ', Colors.white),
    _Word('Instant. ', Colors.white),
    _Word('Inclusive.', Color(0xFF8FE3D8)),
  ];
  static final int _length = _words.fold(0, (sum, w) => sum + w.text.length);
  static final String _fullText = _words.map((w) => w.text).join();

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: _total));

    _controller.forward();
    Future.delayed(const Duration(milliseconds: _total), () {
      if (!mounted) return;
      final nextRoute = SettingsService.instance.userProfile == null
          ? AppRoutes.profileSelection
          : AppRoutes.home;
      Navigator.of(context).pushReplacementNamed(nextRoute);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Position of the writing front, in letters, at [elapsedMs]. Steady speed:
  /// a constant pace is what makes writing feel smooth rather than jumpy.
  double _front(double elapsedMs, {required bool reduceMotion}) {
    if (reduceMotion) return _length + _frontWidth;
    final t = ((elapsedMs - _typeStart) / (_typeEnd - _typeStart)).clamp(0.0, 1.0);
    return t * (_length + _frontWidth);
  }

  /// Draws every letter, each at the opacity set by how far the front has
  /// moved past it. Every letter is always laid out (invisible ones are fully
  /// transparent), so the centred line never shifts as it fills in.
  InlineSpan _buildTagline(double front, TextStyle base) {
    final spans = <InlineSpan>[];
    var index = 0;
    for (final word in _words) {
      for (final char in word.text.characters) {
        final progress = ((front - index) / _frontWidth).clamp(0.0, 1.0);
        final opacity = Curves.easeOut.transform(progress);
        spans.add(TextSpan(
          text: char,
          style: base.copyWith(color: word.color.withValues(alpha: opacity)),
        ));
        index++;
      }
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    const taglineStyle = TextStyle(
      fontFamily: 'Parisienne',
      fontSize: 31,
      letterSpacing: 0.8,
      height: 1.3,
    );
    final screenHeight = MediaQuery.sizeOf(context).height;
    // The tile sits exactly at the centre (like the native launch screen);
    // the tagline hangs below it.
    final taglineTop = screenHeight / 2 + _tileSize / 2 + _tileToTagline;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final elapsedMs = _controller.value * _total;
          // Start as the plain launch colour, then ease into the gradient.
          final blend = Curves.easeOut.transform((elapsedMs / _gradientEnd).clamp(0.0, 1.0));
          final topLeft = Color.lerp(launchColor, AppTheme.navy, blend)!;
          final bottomRight = Color.lerp(launchColor, AppTheme.navyDeep, blend)!;

          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [topLeft, bottomRight],
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: _tileSize,
                    height: _tileSize,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
                    ),
                    child: const Icon(Icons.sign_language, size: 76, color: Colors.white),
                  ),
                ),
                Positioned(
                  top: taglineTop,
                  left: 0,
                  right: 0,
                  child: Semantics(
                    label: _fullText.trim(),
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text.rich(
                          _buildTagline(_front(elapsedMs, reduceMotion: reduceMotion), taglineStyle),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          softWrap: false,
                          // The splash is a fixed composition; the user's
                          // text-size setting must not push it off-screen.
                          textScaler: TextScaler.noScaling,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
