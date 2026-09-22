import 'package:flutter/material.dart';

import '../../../../core/services/settings_service.dart';
import '../../../../routes/app_routes.dart';

/// Shown once, right after the native OS splash hands off to Flutter.
/// Brief branded animation (icon + tagline) before landing on Home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _iconOpacity;
  late final Animation<double> _iconScale;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

    _iconOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _iconScale = Tween(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack)),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );
    _taglineSlide = Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.45, 1.0, curve: Curves.easeOut)),
    );

    _controller.forward();
    Future.delayed(const Duration(milliseconds: 2200), () {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4527A0), Color(0xFF7E57C2)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: _iconOpacity,
                child: ScaleTransition(
                  scale: _iconScale,
                  child: const Icon(Icons.sign_language, size: 120, color: Colors.white),
                ),
              ),
              const SizedBox(height: 28),
              FadeTransition(
                opacity: _taglineOpacity,
                child: SlideTransition(
                  position: _taglineSlide,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'See it. Say it. Understand each other.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
