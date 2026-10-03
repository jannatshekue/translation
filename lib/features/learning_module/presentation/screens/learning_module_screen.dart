import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../../core/profile/app_tools.dart';
import '../../../../core/services/learning_progress_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/lesson.dart';
import '../../../../shared/widgets/action_tile.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../../shared/widgets/section_header.dart';
import 'lesson_detail_screen.dart';

/// The Learn tab: progress at a glance, the next lesson to take, every
/// lesson in order, and a way into teaching the app signs of your own.
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

  Future<void> _open(Lesson lesson) async {
    SettingsService.instance.hapticTap();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => LessonDetailScreen(lesson: lesson)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final done = _completedIds.length;
    final total = _lessons.length;
    final next = _lessons.where((l) => !_completedIds.contains(l.id)).firstOrNull;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _lessons.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 16, AppTheme.screenPadding, 28),
                children: [
                  Text('Learn', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Learn each sign, then practise it with your camera.',
                    style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                done == total ? 'All signs practised' : '$done of $total signs practised',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              '${total == 0 ? 0 : (done * 100 / total).round()}%',
                              style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 8),
                        ),
                        if (next != null) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _open(next),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(done == 0 ? 'Start: ${next.title}' : 'Continue: ${next.title}'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const SectionHeader('Lessons'),
                  SectionCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < _lessons.length; i++) ...[
                          if (i > 0) Divider(height: 1, indent: 64, color: scheme.outlineVariant),
                          _LessonRow(
                            lesson: _lessons[i],
                            number: i + 1,
                            isCompleted: _completedIds.contains(_lessons[i].id),
                            onTap: () => _open(_lessons[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  const SectionHeader('Make it yours'),
                  ActionGroup(
                    children: [
                      ActionTile(
                        icon: AppTool.customSigns.icon,
                        title: AppTool.customSigns.title,
                        subtitle: AppTool.customSigns.subtitle,
                        color: AppTool.customSigns.color,
                        onTap: () => AppTool.customSigns.open(context),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  final Lesson lesson;
  final int number;
  final bool isCompleted;
  final VoidCallback onTap;

  const _LessonRow({
    required this.lesson,
    required this.number,
    required this.isCompleted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCompleted ? AppTheme.success : scheme.surfaceContainerHigh,
              ),
              child: isCompleted
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : Text('$number', style: theme.textTheme.labelLarge),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(lesson.title, style: theme.textTheme.titleMedium)),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
