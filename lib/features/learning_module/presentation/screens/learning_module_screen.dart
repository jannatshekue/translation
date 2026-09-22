import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../../core/services/learning_progress_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../models/lesson.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import 'lesson_detail_screen.dart';

class LearningModuleScreen extends StatefulWidget {
  const LearningModuleScreen({super.key});

  @override
  State<LearningModuleScreen> createState() => _LearningModuleScreenState();
}

class _LearningModuleScreenState extends State<LearningModuleScreen> {
  List<Lesson> _lessons = [];
  Set<String> _completedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final jsonString = await rootBundle.loadString('assets/lessons/lessons.json');
    final decoded = jsonDecode(jsonString) as List<dynamic>;
    final lessons = decoded.map((e) => Lesson.fromMap(e as Map<String, dynamic>)).toList();
    final completedIds = await LearningProgressService.instance.getCompletedLessonIds();
    if (mounted) {
      setState(() {
        _lessons = lessons;
        _completedIds = completedIds;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = _lessons.isEmpty ? 0.0 : _completedIds.length / _lessons.length;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Learning Module'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: _lessons.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Material(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      elevation: 2,
                      shadowColor: Colors.black.withValues(alpha: 0.15),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_completedIds.length} of ${_lessons.length} signs practiced',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 8,
                                backgroundColor: colorScheme.surfaceContainerHighest,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (int index = 0; index < _lessons.length; index++) ...[
                      if (index > 0) const SizedBox(height: 10),
                      _LessonRow(
                        lesson: _lessons[index],
                        index: index,
                        isCompleted: _completedIds.contains(_lessons[index].id),
                        onTap: () async {
                          SettingsService.instance.hapticTap();
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => LessonDetailScreen(lesson: _lessons[index]),
                            ),
                          );
                          await _load();
                        },
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  final Lesson lesson;
  final int index;
  final bool isCompleted;
  final VoidCallback onTap;

  const _LessonRow({
    required this.lesson,
    required this.index,
    required this.isCompleted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + index * 40),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 14), child: child),
      ),
      child: PressableScale(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Material(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  isCompleted ? Icons.check_circle : Icons.circle_outlined,
                  color: isCompleted ? Colors.green : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    lesson.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
