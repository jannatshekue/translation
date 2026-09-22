import 'package:shared_preferences/shared_preferences.dart';

class LearningProgressService {
  LearningProgressService._internal();

  static final LearningProgressService instance = LearningProgressService._internal();

  static const _completedLessonsKey = 'completed_lesson_ids';

  Future<Set<String>> getCompletedLessonIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_completedLessonsKey) ?? const []).toSet();
  }

  Future<void> setLessonCompleted(String lessonId, bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_completedLessonsKey) ?? const []).toSet();
    if (completed) {
      ids.add(lessonId);
    } else {
      ids.remove(lessonId);
    }
    await prefs.setStringList(_completedLessonsKey, ids.toList());
  }
}
