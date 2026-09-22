import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/settings_service.dart';
import '../../../../routes/app_routes.dart';

class _FeatureEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? route;

  const _FeatureEntry(this.title, this.subtitle, this.icon, this.color, {this.route});
}

const _hero = _FeatureEntry(
  'Sign Recognition',
  'Point your camera and start signing',
  Icons.front_hand,
  Colors.deepPurple,
  route: AppRoutes.signRecognition,
);

const _voiceTranslation = _FeatureEntry(
  'Voice Translation',
  'Speech, text & conversation mode',
  Icons.mic,
  Colors.teal,
  route: AppRoutes.voiceTranslation,
);
const _customSigns = _FeatureEntry(
  'Custom Signs',
  'Record your own signs',
  Icons.add_reaction,
  Colors.orange,
  route: AppRoutes.customSigns,
);
const _learningModule = _FeatureEntry(
  'Learning Module',
  'Practice common signs',
  Icons.school,
  Colors.blue,
  route: AppRoutes.learningModule,
);
const _savedPhrases = _FeatureEntry(
  'Saved Phrases',
  'Quick-access phrases',
  Icons.bookmark,
  Colors.pink,
  route: AppRoutes.savedPhrases,
);
const _emergencyMode = _FeatureEntry(
  'Emergency Mode',
  'One-tap alert with location',
  Icons.emergency,
  Colors.red,
  route: AppRoutes.emergencyMode,
);
const _settings = _FeatureEntry(
  'Settings',
  'Appearance & accessibility',
  Icons.settings,
  Colors.blueGrey,
  route: AppRoutes.settings,
);

/// Same 6 features for everyone, just reordered so the most relevant tools
/// for the active accessibility profile surface first. Nothing is ever
/// hidden — every feature remains one tap away regardless of profile.
List<_FeatureEntry> _featuresFor(UserProfile? profile) {
  switch (profile) {
    case UserProfile.hearingImpaired:
    case UserProfile.speechImpaired:
      return [_customSigns, _learningModule, _voiceTranslation, _savedPhrases, _emergencyMode, _settings];
    case UserProfile.normal:
    case null:
      return [_voiceTranslation, _customSigns, _learningModule, _savedPhrases, _emergencyMode, _settings];
  }
}

void _open(BuildContext context, _FeatureEntry feature) {
  SettingsService.instance.hapticTap();
  final route = feature.route;
  if (route != null) {
    Navigator.of(context).pushNamed(route);
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('${feature.title} screen not built yet')),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: AnimatedBuilder(
        animation: SettingsService.instance,
        builder: (context, _) => _buildBody(context, colorScheme),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colorScheme) {
    final features = _featuresFor(SettingsService.instance.userProfile);

    return Stack(
        children: [
          // Base gradient.
          DecoratedBox(
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
            child: const SizedBox.expand(),
          ),
          // Soft decorative color blobs for a less flat, more modern feel.
          Positioned(
            top: -90,
            right: -70,
            child: _blob(colorScheme.primary.withValues(alpha: 0.35), 260),
          ),
          Positioned(
            bottom: -60,
            left: -80,
            child: _blob(colorScheme.tertiary.withValues(alpha: 0.28), 240),
          ),
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sign & Voice Translator',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  sliver: SliverToBoxAdapter(child: _HeroCard(feature: _hero)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'More tools',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.98,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _FeatureTile(feature: features[index], index: index),
                      childCount: features.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
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

/// Large, prominent entry point for the app's flagship feature — the clear
/// call-to-action rather than one row among equals.
class _HeroCard extends StatefulWidget {
  final _FeatureEntry feature;

  const _HeroCard({required this.feature});

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 16), child: child),
      ),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Material(
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          elevation: _pressed ? 1 : 6,
          shadowColor: colorScheme.primary.withValues(alpha: 0.4),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colorScheme.primary, colorScheme.tertiary],
              ),
            ),
            child: InkWell(
              splashColor: Colors.white.withValues(alpha: 0.15),
              highlightColor: Colors.white.withValues(alpha: 0.08),
              onTap: () => _open(context, widget.feature),
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(widget.feature.icon, color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.feature.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.feature.subtitle,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatefulWidget {
  final _FeatureEntry feature;
  final int index;

  const _FeatureTile({required this.feature, required this.index});

  @override
  State<_FeatureTile> createState() => _FeatureTileState();
}

class _FeatureTileState extends State<_FeatureTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final feature = widget.feature;
    final colorScheme = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + widget.index * 60),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 18), child: child),
      ),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Material(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          elevation: _pressed ? 0 : 2,
          shadowColor: Colors.black.withValues(alpha: 0.15),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            splashColor: feature.color.withValues(alpha: 0.18),
            highlightColor: feature.color.withValues(alpha: 0.10),
            onTap: () {
              HapticFeedback.selectionClick();
              _open(context, feature);
            },
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: feature.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(feature.icon, color: feature.color, size: 24),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    feature.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    feature.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
