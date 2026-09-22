import 'package:flutter_test/flutter_test.dart';
import 'package:hand_detection/hand_detection.dart';
import 'package:translation/core/services/hand_pose_matcher.dart';

/// Builds a synthetic, non-degenerate 21-landmark hand pose. Each landmark
/// gets a distinct position based on its index in [HandLandmarkType.values],
/// then [offsets] lets a test nudge specific landmarks to shape a "pose".
List<HandLandmark> _buildHand({
  double dx = 0,
  double dy = 0,
  double scale = 1,
  Map<HandLandmarkType, Offset> offsets = const {},
}) {
  return [
    for (final type in HandLandmarkType.values)
      HandLandmark(
        type: type,
        x: dx + scale * (HandLandmarkType.values.indexOf(type) * 10 + (offsets[type]?.dx ?? 0)),
        y: dy + scale * (HandLandmarkType.values.indexOf(type) * 5 + (offsets[type]?.dy ?? 0)),
        z: 0,
        visibility: 1.0,
      ),
  ];
}

List<Map<String, dynamic>> _toMaps(List<HandLandmark> landmarks) =>
    landmarks.map((l) => l.toMap()).toList();

void main() {
  group('normalizeFrame', () {
    test('returns null when fewer than 21 landmarks are given', () {
      final hand = _buildHand().sublist(0, 20);
      expect(HandPoseMatcher.normalizeFrame(hand), isNull);
    });

    test('returns null when wrist and middle-MCP coincide (zero scale)', () {
      final hand = _buildHand(offsets: {
        // middleFingerMCP index is 9, whose base position is
        // (index*10, index*5) = (90, 45); this offset cancels that back to
        // (0, 0), coinciding with the wrist and making scale ~0.
        HandLandmarkType.middleFingerMCP: const Offset(-90, -45),
      });
      expect(HandPoseMatcher.normalizeFrame(hand), isNull);
    });

    test('is invariant to translation (same pose, shifted position)', () {
      final base = HandPoseMatcher.normalizeFrame(_buildHand());
      final shifted = HandPoseMatcher.normalizeFrame(_buildHand(dx: 500, dy: -300));
      expect(base, isNotNull);
      expect(shifted, isNotNull);
      for (var i = 0; i < base!.length; i++) {
        expect(shifted![i], closeTo(base[i], 1e-9));
      }
    });

    test('is invariant to uniform scale (same pose, closer/farther from camera)', () {
      final base = HandPoseMatcher.normalizeFrame(_buildHand());
      final scaledUp = HandPoseMatcher.normalizeFrame(_buildHand(scale: 3));
      expect(base, isNotNull);
      expect(scaledUp, isNotNull);
      for (var i = 0; i < base!.length; i++) {
        expect(scaledUp![i], closeTo(base[i], 1e-9));
      }
    });

    test('a genuinely different hand shape produces a different vector', () {
      final open = HandPoseMatcher.normalizeFrame(_buildHand());
      final fist = HandPoseMatcher.normalizeFrame(_buildHand(offsets: {
        HandLandmarkType.indexFingerTip: const Offset(-20, -8),
        HandLandmarkType.middleFingerTip: const Offset(-20, -8),
        HandLandmarkType.ringFingerTip: const Offset(-20, -8),
        HandLandmarkType.pinkyTip: const Offset(-20, -8),
      }));
      expect(HandPoseMatcher.distance(open!, fist!), greaterThan(0.01));
    });
  });

  group('normalizeFrameFromMaps', () {
    test('round-trips through HandLandmark.toMap/fromMap identically to normalizeFrame', () {
      final hand = _buildHand();
      final direct = HandPoseMatcher.normalizeFrame(hand);
      final viaMaps = HandPoseMatcher.normalizeFrameFromMaps(_toMaps(hand));
      expect(viaMaps, isNotNull);
      for (var i = 0; i < direct!.length; i++) {
        expect(viaMaps![i], closeTo(direct[i], 1e-9));
      }
    });
  });

  group('computeTemplate', () {
    test('returns null for an empty frame list', () {
      expect(HandPoseMatcher.computeTemplate([]), isNull);
    });

    test('averages the normalized vectors of multiple frames', () {
      final frameA = _toMaps(_buildHand(dx: 0));
      final frameB = _toMaps(_buildHand(dx: 500)); // translation-invariant, so should match frameA
      final template = HandPoseMatcher.computeTemplate([frameA, frameB]);
      final expected = HandPoseMatcher.normalizeFrame(_buildHand());
      expect(template, isNotNull);
      for (var i = 0; i < expected!.length; i++) {
        expect(template![i], closeTo(expected[i], 1e-9));
      }
    });

    test('skips unusable frames (e.g. degenerate scale) instead of failing outright', () {
      final good = _toMaps(_buildHand());
      final degenerate = _toMaps(_buildHand(offsets: {
        HandLandmarkType.middleFingerMCP: const Offset(-90, -45),
      }));
      final template = HandPoseMatcher.computeTemplate([good, degenerate]);
      final expected = HandPoseMatcher.normalizeFrame(_buildHand());
      expect(template, isNotNull);
      for (var i = 0; i < expected!.length; i++) {
        expect(template![i], closeTo(expected[i], 1e-9));
      }
    });
  });

  group('distance', () {
    test('is zero between a vector and itself', () {
      final v = HandPoseMatcher.normalizeFrame(_buildHand())!;
      expect(HandPoseMatcher.distance(v, v), closeTo(0, 1e-12));
    });

    test('is symmetric', () {
      final a = HandPoseMatcher.normalizeFrame(_buildHand())!;
      final b = HandPoseMatcher.normalizeFrame(_buildHand(offsets: {
        HandLandmarkType.thumbTip: const Offset(5, 5),
      }))!;
      expect(HandPoseMatcher.distance(a, b), closeTo(HandPoseMatcher.distance(b, a), 1e-12));
    });
  });
}

class Offset {
  final double dx;
  final double dy;
  const Offset(this.dx, this.dy);
}
