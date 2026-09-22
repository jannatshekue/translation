import 'package:flutter/material.dart';

import '../../../../core/services/learning_progress_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../models/lesson.dart';
import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../../shared/widgets/pressable_scale.dart';
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Icon(Icons.front_hand, size: 56, color: colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                widget.lesson.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              SectionCard(
                child: Text(widget.lesson.description, style: Theme.of(context).textTheme.bodyLarge),
              ),
              const SizedBox(height: 20),
              PressableScale(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  SettingsService.instance.hapticTap();
                  Navigator.of(context).pushNamed(AppRoutes.signRecognition);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.front_hand, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(
                        'Practice with camera',
                        style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PressableScale(
                borderRadius: BorderRadius.circular(16),
                onTap: _toggleCompletion,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: _isCompleted ? Colors.green : colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isCompleted ? Icons.check_circle : Icons.check_circle_outline,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isCompleted ? 'Completed' : 'Mark as complete',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
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
