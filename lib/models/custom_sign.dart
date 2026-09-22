import 'dart:convert';

class CustomSign {
  final int id;
  final String label;
  final String landmarkSequenceJson;
  final DateTime createdAt;

  const CustomSign({
    required this.id,
    required this.label,
    required this.landmarkSequenceJson,
    required this.createdAt,
  });

  factory CustomSign.fromMap(Map<String, Object?> map) => CustomSign(
        id: map['id'] as int,
        label: map['label'] as String,
        landmarkSequenceJson: map['landmark_sequence'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  List<List<Map<String, dynamic>>> get decodedFrames {
    final frames = jsonDecode(landmarkSequenceJson) as List<dynamic>;
    return frames
        .map((frame) => (frame as List<dynamic>).cast<Map<String, dynamic>>())
        .toList();
  }
}
