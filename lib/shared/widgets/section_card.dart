import 'package:flutter/material.dart';

/// Consistent rounded, elevated card used to group content across screens
/// (form sections, status panels, list containers), matching the styling
/// introduced on the home screen's feature tiles.
class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: Padding(padding: padding, child: child),
    );
  }
}
