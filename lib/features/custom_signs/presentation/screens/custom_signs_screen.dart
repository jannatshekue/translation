import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hand_detection/hand_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/services/hand_detection_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/utils/app_permissions.dart';
import '../../../../models/custom_sign.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../../shared/widgets/section_header.dart';

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
    final granted = await AppPermissions.ensure(context, Permission.camera, announceDenial: false);
    if (!granted) {
      if (mounted) setState(() => _status = AppPermissions.neededMessage(Permission.camera));
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasLabel = _labelController.text.trim().isNotEmpty;
    final canSave = !_isRecording && _capturedFrames.isNotEmpty && hasLabel;

    return Scaffold(
      appBar: AppBar(title: const Text('My custom signs')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTheme.screenPadding, 0, AppTheme.screenPadding, 28),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: controller != null && controller.value.isInitialized
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(controller),
                          if (_isRecording)
                            Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                margin: const EdgeInsets.only(top: 14),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.emergency,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  '● RECORDING',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1),
                                ),
                              ),
                            ),
                        ],
                      )
                    : Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _isRecording ? scheme.outline : AppTheme.emergency,
                foregroundColor: Colors.white,
              ),
              onPressed: controller == null || _isRecording ? null : _startRecording,
              icon: const Icon(Icons.fiber_manual_record),
              label: Text(_isRecording ? 'Recording…' : 'Record the sign (2 seconds)'),
            ),
            const SizedBox(height: 20),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Name this sign', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _labelController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'e.g. "Water" or "Mama"'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: canSave ? _saveSign : null,
                    child: const Text('Save sign'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const SectionHeader('Saved signs'),
            if (_savedSigns.isEmpty)
              SectionCard(
                child: Text(
                  'No custom signs saved yet. Record one above.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              )
            else
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < _savedSigns.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        title: Text(_savedSigns[i].label, style: theme.textTheme.titleMedium),
                        subtitle: Text(_formatDate(_savedSigns[i].createdAt)),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: Icon(Icons.delete_outline, color: scheme.error),
                          onPressed: () => _deleteSign(_savedSigns[i].id),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
