import 'package:hand_detection/hand_detection.dart';

import '../../models/custom_sign.dart';
import 'database_service.dart';
import 'hand_pose_matcher.dart';

class CustomSignMatch {
  final CustomSign sign;
  final double distance;

  const CustomSignMatch(this.sign, this.distance);
}

/// Matches a live hand pose against saved custom signs. Call [loadTemplates]
/// once per screen session (custom signs rarely change mid-session), then
/// [match] per detected hand.
class CustomSignRecognizer {
  CustomSignRecognizer._internal();

  static final CustomSignRecognizer instance = CustomSignRecognizer._internal();

  /// Empirically reasonable cutoff for the normalized landmark distance;
  /// signs with very different hand shapes fall well above this.
  static const matchThreshold = 0.5;

  List<MapEntry<CustomSign, List<double>>> _templates = [];

  Future<void> loadTemplates() async {
    final signs = await DatabaseService.instance.getCustomSigns();
    final templates = <MapEntry<CustomSign, List<double>>>[];
    for (final sign in signs) {
      final template = HandPoseMatcher.computeTemplate(sign.decodedFrames);
      if (template != null) {
        templates.add(MapEntry(sign, template));
      }
    }
    _templates = templates;
  }

  CustomSignMatch? match(List<HandLandmark> landmarks) {
    if (_templates.isEmpty) return null;
    final vector = HandPoseMatcher.normalizeFrame(landmarks);
    if (vector == null) return null;

    CustomSign? bestSign;
    var bestDistance = double.infinity;
    for (final entry in _templates) {
      final d = HandPoseMatcher.distance(vector, entry.value);
      if (d < bestDistance) {
        bestDistance = d;
        bestSign = entry.key;
      }
    }
    if (bestSign == null || bestDistance > matchThreshold) return null;
    return CustomSignMatch(bestSign, bestDistance);
  }
}
