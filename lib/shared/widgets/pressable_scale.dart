import 'package:flutter/material.dart';

/// Reusable tap target: scales down, drops its (caller-supplied) elevation,
/// and shows a ripple on press. Used everywhere instead of a bare InkWell so
/// every interactive surface in the app feels the same and is obviously
/// pressable, addressing feedback that taps used to feel invisible.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Color? splashColor;
  final Color? highlightColor;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.splashColor,
    this.highlightColor,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: Material(
        color: Colors.transparent,
        borderRadius: widget.borderRadius,
        child: InkWell(
          borderRadius: widget.borderRadius,
          splashColor: widget.splashColor,
          highlightColor: widget.highlightColor,
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: widget.child,
        ),
      ),
    );
  }
}
