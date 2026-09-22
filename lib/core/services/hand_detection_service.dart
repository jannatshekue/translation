import 'dart:typed_data';

import 'package:hand_detection/hand_detection.dart';

/// Recommended cap for live-camera detection frames — matches the package's
/// own example. Keeps per-frame inference fast without hurting accuracy;
/// full camera resolution isn't needed for palm/landmark detection.
const int liveDetectionMaxDim = 640;

/// Wraps `hand_detection` (on-device palm detection + 21-point landmarks).
/// This is the input stage for sign recognition: callers feed frame bytes in
/// and get back landmarks per detected hand, which the sign classifier
/// (trained separately, see ml_training/) turns into a predicted sign.
class HandDetectionService {
  HandDetectionService._internal();

  static final HandDetectionService instance = HandDetectionService._internal();

  HandDetector? _detector;

  Future<void> initialize() async {
    // enableTracking follows each hand's region of interest between frames
    // instead of re-running full palm detection every frame — faster and
    // much less flicker on a live camera feed (see package docs).
    _detector ??= await HandDetector.create(
      enableGestures: true,
      enableTracking: true,
    );
  }

  /// Detects hands directly from a live camera frame (used by the sign
  /// recognition screen's image stream). Cheaper than [detectHands] since it
  /// skips JPEG encode/decode. Pass [rotation] (from [rotationForFrame]) so
  /// returned landmark coordinates are upright and overlay painters can map
  /// them correctly. [maxDim] downscales the frame before detection —
  /// pass the same value to [detectionSize] when computing an overlay's
  /// source size so the two stay in sync.
  Future<List<Hand>> detectHandsFromCameraImage(
    Object cameraImage, {
    CameraFrameRotation? rotation,
    int? maxDim,
  }) async {
    final detector = _detector;
    if (detector == null) {
      throw StateError('HandDetectionService not initialized. Call initialize() first.');
    }
    return detector.detectFromCameraImage(cameraImage, rotation: rotation, maxDim: maxDim);
  }

  /// Detects hands in a single encoded image frame (e.g. JPEG bytes from the
  /// camera). Returns one entry per detected hand, each with up to 21
  /// landmarks (x, y, z, visibility).
  Future<List<Hand>> detectHands(Uint8List frameBytes) async {
    final detector = _detector;
    if (detector == null) {
      throw StateError('HandDetectionService not initialized. Call initialize() first.');
    }
    return detector.detect(frameBytes);
  }

  Future<void> dispose() async {
    await _detector?.dispose();
    _detector = null;
  }
}
