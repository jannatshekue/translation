class SavedPhrase {
  final int id;
  final String text;
  final DateTime createdAt;

  const SavedPhrase({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  factory SavedPhrase.fromMap(Map<String, Object?> map) => SavedPhrase(
        id: map['id'] as int,
        text: map['text'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}
