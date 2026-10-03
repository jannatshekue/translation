import 'package:flutter/material.dart';

/// Rounded-square icon holder used to lead rows and cards.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;

  const IconBadge(this.icon, {super.key, this.color, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: tint, size: size * 0.5),
    );
  }
}
