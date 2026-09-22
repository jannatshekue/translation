import 'dart:math';

import 'package:hand_detection/hand_detection.dart';

/// Lightweight, on-device template matching for custom signs: normalizes a
/// hand's landmarks (translate to wrist origin, scale by palm length) so the
/// result is invariant to hand position and distance from the camera, then
/// compares against saved templates by Euclidean distance. This is the
/// approach the project design calls for instead of retraining a model per
/// new sign.
class HandPoseMatcher {
  HandPoseMatcher._();

  static List<double>? normalizeFrame(List<HandLandmark> landmarks) {
    if (landmarks.length < 21) return null;
    final byType = {for (final l in landmarks) l.type: l};
    final wrist = byType[HandLandmarkType.wrist];
    final middleMcp = byType[HandLandmarkType.middleFingerMCP];
    if (wrist == null || middleMcp == null) return null;

    final scale = sqrt(
      pow(middleMcp.x - wrist.x, 2) + pow(middleMcp.y - wrist.y, 2),
    );
    if (scale < 1e-6) return null;

    final vector = <double>[];
    for (final type in HandLandmarkType.values) {
      final point = byType[type];
      if (point == null) return null;
      vector.add((point.x - wrist.x) / scale);
      vector.add((point.y - wrist.y) / scale);
    }
    return vector;
  }

  static List<double>? normalizeFrameFromMaps(List<Map<String, dynamic>> frame) {
    final landmarks = frame.map(HandLandmark.fromMap).toList();
    return normalizeFrame(landmarks);
  }

  /// Averages normalized per-frame vectors from a recorded sequence into a
  /// single template vector.
  static List<double>? computeTemplate(List<List<Map<String, dynamic>>> frames) {
    final vectors = frames.map(normalizeFrameFromMaps).whereType<List<double>>().toList();
    if (vectors.isEmpty) return null;
    final length = vectors.first.length;
    final sums = List<double>.filled(length, 0);
    for (final v in vectors) {
      for (var i = 0; i < length; i++) {
        sums[i] += v[i];
      }
    }
    return sums.map((s) => s / vectors.length).toList();
  }

  static double distance(List<double> a, List<double> b) {
    var sum = 0.0;
    for (var i = 0; i < a.length; i++) {
      final d = a[i] - b[i];
      sum += d * d;
    }
    return sqrt(sum);
  }
}
