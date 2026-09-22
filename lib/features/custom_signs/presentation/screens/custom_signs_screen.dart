import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/services/hand_detection_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/utils/permission_primer.dart';
import '../../../../models/custom_sign.dart';
import '../../../../shared/widgets/app_background.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../../../shared/widgets/section_card.dart';

/// Records a short landmark sequence for a hand sign the built-in gesture
/// set doesn't cover, and labels it. Recognizing these against a live feed
/// (template matching against the saved sequences) is handled by
/// CustomSignRecognizer in the sign recognition screen.
class CustomSignsScreen extends StatefulWidget {
  const CustomSignsScreen({super.key});

  @override
  State<CustomSignsScreen> createState() => _CustomSignsScreenState();
}

class _CustomSignsScreenState extends State<CustomSignsScreen> {
  static const _recordDuration = Duration(seconds: 2);

  CameraController? _controller;
  int? _sensorOrientation;
  bool _isFrontCamera = false;

  String _status = 'Starting camera…';
  bool _isRecording = false;
  bool _isProcessingFrame = false;
  final List<List<Map<String, dynamic>>> _capturedFrames = [];
  final TextEditingController _labelController = TextEditingController();

  List<CustomSign> _savedSigns = [];

  @override
  void initState() {
    super.initState();
    _setup();
    _loadSavedSigns();
  }

  Future<void> _loadSavedSigns() async {
    final signs = await DatabaseService.instance.getCustomSigns();
    if (mounted) setState(() => _savedSigns = signs);
  }

  Future<void> _setup() async {
    if (!mounted) return;
    final granted = await PermissionPrimer.requestWithRationale(
      context,
      permission: Permission.camera,
      title: 'Camera access',
      message: 'Custom Signs needs your camera to record the hand sign you\'re saving.',
    );
    if (!granted) {
      setState(() => _status = 'Camera permission denied.');
      return;
    }

    try {
      await HandDetectionService.instance.initialize();

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
        _status = 'Hold the sign, then tap Record';
      });
      await controller.startImageStream(_onCameraFrame);
    } catch (e) {
      if (mounted) setState(() => _status = 'Camera error: $e');
    }
  }

  Future<void> _onCameraFrame(CameraImage image) async {
    if (!_isRecording || _isProcessingFrame) return;
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
      if (hands.isNotEmpty) {
        _capturedFrames.add(hands.first.landmarks.map((l) => l.toMap()).toList());
      }
    } catch (_) {
      // Drop this frame; recording continues.
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _startRecording() async {
    SettingsService.instance.hapticTap();
    _capturedFrames.clear();
    setState(() {
      _isRecording = true;
      _status = 'Recording…';
    });
    await Future.delayed(_recordDuration);
    setState(() {
      _isRecording = false;
      _status = _capturedFrames.isEmpty
          ? 'No hand detected during recording. Try again.'
          : 'Captured ${_capturedFrames.length} frames. Enter a label and save.';
    });
    SettingsService.instance.hapticImpact();
  }

  Future<void> _saveSign() async {
    final label = _labelController.text.trim();
    if (label.isEmpty || _capturedFrames.isEmpty) return;

    await DatabaseService.instance.insertCustomSign(
      label: label,
      landmarkSequenceJson: jsonEncode(_capturedFrames),
    );
    SettingsService.instance.hapticTap();
    _capturedFrames.clear();
    _labelController.clear();
    setState(() => _status = 'Hold the sign, then tap Record');
    await _loadSavedSigns();
  }

  Future<void> _deleteSign(int id) async {
    SettingsService.instance.hapticTap();
    await DatabaseService.instance.deleteCustomSign(id);
    await _loadSavedSigns();
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    HandDetectionService.instance.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final canSave = !_isRecording && _capturedFrames.isNotEmpty;

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Custom Signs')),
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: controller != null && controller.value.isInitialized
                        ? CameraPreview(controller)
                        : Container(color: Colors.black, child: Center(child: Text(_status))),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: PressableScale(
                        borderRadius: BorderRadius.circular(32),
                        onTap: controller == null || _isRecording ? null : _startRecording,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          decoration: BoxDecoration(
                            color: _isRecording ? Colors.grey : Colors.red,
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.fiber_manual_record, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _isRecording ? 'Recording…' : 'Record (2s)',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _labelController,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Sign label',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          PressableScale(
                            borderRadius: BorderRadius.circular(12),
                            onTap: canSave && _labelController.text.trim().isNotEmpty ? _saveSign : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: canSave && _labelController.text.trim().isNotEmpty
                                    ? colorScheme.primary
                                    : colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  'Save sign',
                                  style: TextStyle(
                                    color: canSave && _labelController.text.trim().isNotEmpty
                                        ? colorScheme.onPrimary
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Saved signs',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (_savedSigns.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No custom signs saved yet',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      )
                    else
                      for (final sign in _savedSigns) ...[
                        Material(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          elevation: 1,
                          shadowColor: Colors.black.withValues(alpha: 0.1),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            title: Text(sign.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(sign.createdAt.toLocal().toString()),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: colorScheme.error),
                              onPressed: () => _deleteSign(sign.id),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
