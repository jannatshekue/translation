import 'package:flutter/material.dart';

import '../services/settings_service.dart';

/// Briefly flashes the screen white — a visual alert for deaf/hard-of-hearing
/// users, alongside (or instead of) vibration. Gated by the flash-alerts
/// setting, same pattern as the haptic helpers.
class FlashAlert {
  FlashAlert._();

  static void trigger(BuildContext context) {
    if (!SettingsService.instance.flashAlertsEnabled) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _FlashOverlay(onComplete: () => entry.remove()),
    );
    overlay.insert(entry);
  }
}

class _FlashOverlay extends StatefulWidget {
  final VoidCallback onComplete;

  const _FlashOverlay({required this.onComplete});

  @override
  State<_FlashOverlay> createState() => _FlashOverlayState();
}

class _FlashOverlayState extends State<_FlashOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.85), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.85, end: 0.0), weight: 1),
    ]).animate(_controller);
    _controller.forward().whenComplete(widget.onComplete);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _opacity,
        builder: (context, _) => Container(color: Colors.white.withValues(alpha: _opacity.value)),
      ),
    );
  }
}
