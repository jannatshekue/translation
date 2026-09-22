import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared background treatment used across every screen: a subtle gradient
/// plus two soft blurred color blobs, instead of a flat single-color fill.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.surface,
                  Color.alphaBlend(colorScheme.primary.withValues(alpha: 0.10), colorScheme.surface),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -70,
          child: _blob(colorScheme.primary.withValues(alpha: 0.30), 260),
        ),
        Positioned(
          bottom: -60,
          left: -80,
          child: _blob(colorScheme.tertiary.withValues(alpha: 0.24), 240),
        ),
        child,
      ],
    );
  }

  static Widget _blob(Color color, double size) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
