import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_detection/hand_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/services/custom_sign_recognizer.dart';
import '../../../../core/services/hand_detection_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/sign_classifier_service.dart';
import '../../../../core/services/tts_service.dart';
import '../../../../core/utils/flash_alert.dart';
import '../../../../core/utils/permission_primer.dart';

class SignRecognitionScreen extends StatefulWidget {
  const SignRecognitionScreen({super.key});

  @override
  State<SignRecognitionScreen> createState() => _SignRecognitionScreenState();
}

class _SignRecognitionScreenState extends State<SignRecognitionScreen> {
  CameraController? _controller;
  int? _sensorOrientation;
  bool _isFrontCamera = false;

  String _status = 'Starting camera…';
  List<Hand> _hands = const [];
  Size? _imageSize;
  String? _recognizedLabel;
  bool _isProcessingFrame = false;
  String? _lastSpokenLabel;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    if (!mounted) return;
    final granted = await PermissionPrimer.requestWithRationale(
      context,
      permission: Permission.camera,
      title: 'Camera access',
      message: 'Sign Recognition needs your camera to see and recognize hand signs.',
    );
    if (!granted) {
      setState(() => _status = 'Camera permission denied.');
      return;
    }

    try {
      await HandDetectionService.instance.initialize();
      await CustomSignRecognizer.instance.loadTemplates();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _status = 'No camera found on this device.');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _sensorOrientation = camera.sensorOrientation;
        _isFrontCamera = camera.lensDirection == CameraLensDirection.front;
        _status = 'Show a hand sign to the camera';
      });
      await controller.startImageStream(_onCameraFrame);
    } catch (e) {
      if (mounted) setState(() => _status = 'Camera error: $e');
    }
  }

  Future<void> _onCameraFrame(CameraImage image) async {
    if (_isProcessingFrame) return;
    _isProcessingFrame = true;
    try {
      final controller = _controller;
      final sensorOrientation = _sensorOrientation;
      CameraFrameRotation? rotation;
      if (controller != null && sensorOrientation != null) {
        rotation = rotationForFrame(
          width: image.width,
          height: image.height,
          sensorOrientation: sensorOrientation,
          isFrontCamera: _isFrontCamera,
          deviceOrientation: controller.value.deviceOrientation,
        );
      }

      final hands = await HandDetectionService.instance.detectHandsFromCameraImage(
        image,
        rotation: rotation,
        maxDim: liveDetectionMaxDim,
      );
      if (!mounted) return;

      final imageSize = detectionSize(
        width: image.width,
        height: image.height,
        rotation: rotation,
        maxDim: liveDetectionMaxDim,
      );
      final label = await _resolveLabel(hands);
      if (!mounted) return;
      setState(() {
        _hands = hands;
        _imageSize = imageSize;
        _recognizedLabel = label;
      });
      await _maybeSpeak(label);
    } catch (_) {
      // Drop this frame; the next one will retry.
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Priority: the user's own Custom Signs first (most specific to them),
  /// then the built-in gesture set (a dedicated, purpose-built classifier
  /// for its own small fixed vocabulary — cheap and safe to check first
  /// since it reports `unknown` rather than guessing), then the trained
  /// sign-language classifier as the final fallback. The trained classifier
  /// must go last: it's a closed-set classifier over its own vocabulary, so
  /// it will confidently mislabel out-of-vocabulary poses (e.g. a thumbs-up)
  /// as some letter/word instead of admitting it doesn't know — checking
  /// gestures first prevents that false match from ever being reached.
  Future<String?> _resolveLabel(List<Hand> hands) async {
    if (hands.isEmpty) return null;
    final landmarks = hands.first.landmarks;
    if (landmarks.isNotEmpty) {
      final customMatch = CustomSignRecognizer.instance.match(landmarks);
      if (customMatch != null) return customMatch.sign.label;
    }

    final gesture = hands.first.gesture;
    if (gesture != null && gesture.type != GestureType.unknown) {
      return _gestureLabel(gesture.type);
    }

    if (landmarks.isNotEmpty) {
      final trainedMatch = await SignClassifierService.instance.classify(
        landmarks,
        language: SettingsService.instance.signLanguage,
      );
      if (trainedMatch != null) return trainedMatch.label;
    }
    return null;
  }

  Future<void> _maybeSpeak(String? label) async {
    if (label == null) {
      _lastSpokenLabel = null;
      return;
    }
    if (label == _lastSpokenLabel) return;
    _lastSpokenLabel = label;
    SettingsService.instance.hapticImpact();
    if (mounted) FlashAlert.trigger(context);
    await TtsService.instance.speak(label);
  }

  String _gestureLabel(GestureType type) {
    switch (type) {
      case GestureType.thumbUp:
        return 'Thumbs up';
      case GestureType.thumbDown:
        return 'Thumbs down';
      case GestureType.victory:
        return 'Victory';
      case GestureType.closedFist:
        return 'Closed fist';
      case GestureType.openPalm:
        return 'Open palm';
      case GestureType.pointingUp:
        return 'Pointing up';
      case GestureType.iLoveYou:
        return 'I love you';
      case GestureType.unknown:
        return '';
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    HandDetectionService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final imageSize = _imageSize;
    final cameraReady = controller != null && controller.value.isInitialized;

    final cameraAspectRatio = cameraReady ? controller.value.aspectRatio : 1.0;
    final isPortrait = cameraReady &&
        (controller.value.deviceOrientation == DeviceOrientation.portraitUp ||
            controller.value.deviceOrientation == DeviceOrientation.portraitDown);
    final displayAspectRatio = isPortrait ? 1.0 / cameraAspectRatio : cameraAspectRatio;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Sign Recognition'),
        backgroundColor: Colors.black.withValues(alpha: 0.25),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (cameraReady)
            Center(
              child: AspectRatio(
                aspectRatio: displayAspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(controller),
                    if (imageSize != null)
                      CustomPaint(
                        painter: CameraHandOverlayPainter(
                          hands: _hands,
                          imageSize: imageSize,
                          mirrorHorizontally: _isFrontCamera,
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: Text(_status, style: const TextStyle(color: Colors.white70)),
            ),
          if (_recognizedLabel != null)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedScale(
                  scale: 1.0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF7E57C2), Color(0xFF4527A0)]),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12),
                      ],
                    ),
                    child: Text(
                      _recognizedLabel!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _hands.isEmpty ? _status : '${_hands.length} hand(s) detected',
                style: const TextStyle(color: Colors.white, fontSize: 15),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
