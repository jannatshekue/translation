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
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/flash_alert.dart';
import '../../../../core/utils/app_permissions.dart';

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
    final granted = await AppPermissions.ensure(context, Permission.camera, announceDenial: false);
    if (!granted) {
      if (mounted) setState(() => _status = AppPermissions.neededMessage(Permission.camera));
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
    final theme = Theme.of(context);

    final cameraAspectRatio = cameraReady ? controller.value.aspectRatio : 1.0;
    final isPortrait = cameraReady &&
        (controller.value.deviceOrientation == DeviceOrientation.portraitUp ||
            controller.value.deviceOrientation == DeviceOrientation.portraitDown);
    final displayAspectRatio = isPortrait ? 1.0 / cameraAspectRatio : cameraAspectRatio;
    final label = _recognizedLabel;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Sign recognition'),
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
        backgroundColor: Colors.transparent,
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
              padding: const EdgeInsets.all(32),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
          // Dark scrims keep the title and caption readable on any background.
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                  stops: const [0, 0.22, 0.6, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    color: label != null
                        ? Colors.white
                        : Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: label != null
                      ? Row(
                          children: [
                            const Icon(Icons.volume_up, color: AppTheme.navy),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                label,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: AppTheme.navy,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        )
                      : Text(
                          _hands.isEmpty ? _status : 'Hand found — hold the sign steady',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
