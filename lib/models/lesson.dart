class Lesson {
  final String id;
  final String title;
  final String description;

  const Lesson({
    required this.id,
    required this.title,
    required this.description,
  });

  factory Lesson.fromMap(Map<String, dynamic> map) => Lesson(
        id: map['id'] as String,
        title: map['title'] as String,
        description: map['description'] as String,
      );
}
