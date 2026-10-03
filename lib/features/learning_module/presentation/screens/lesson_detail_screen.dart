import 'package:flutter/material.dart';

import '../../../../core/services/learning_progress_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/lesson.dart';
import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/section_card.dart';

class LessonDetailScreen extends StatefulWidget {
  final Lesson lesson;

  const LessonDetailScreen({super.key, required this.lesson});

  @override
  State<LessonDetailScreen> createState() => _LessonDetailScreenState();
}

class _LessonDetailScreenState extends State<LessonDetailScreen> {
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _loadCompletion();
  }

  Future<void> _loadCompletion() async {
    final ids = await LearningProgressService.instance.getCompletedLessonIds();
    if (mounted) setState(() => _isCompleted = ids.contains(widget.lesson.id));
  }

  Future<void> _toggleCompletion() async {
    final next = !_isCompleted;
    SettingsService.instance.hapticImpact();
    await LearningProgressService.instance.setLessonCompleted(widget.lesson.id, next);
    if (mounted) setState(() => _isCompleted = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 0, AppTheme.screenPadding, 24),
          children: [
            Container(
              height: 150,
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient(context),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(child: Icon(Icons.front_hand, size: 64, color: Colors.white)),
            ),
            const SizedBox(height: 20),
            Text(widget.lesson.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 14),
            SectionCard(
              child: Text(widget.lesson.description, style: theme.textTheme.bodyLarge),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  SettingsService.instance.hapticTap();
                  Navigator.of(context).pushNamed(AppRoutes.signRecognition);
                },
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Practise with the camera'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: _isCompleted ? FilledButton.styleFrom(backgroundColor: AppTheme.success) : null,
                onPressed: _toggleCompletion,
                icon: Icon(_isCompleted ? Icons.check_circle : Icons.check_circle_outline),
                label: Text(_isCompleted ? 'Completed' : 'Mark as complete'),
              ),
            ),
            if (_isCompleted)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Tap again to undo.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
