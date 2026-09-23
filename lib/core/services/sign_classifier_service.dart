import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hand_detection/hand_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'hand_pose_matcher.dart';

/// Which trained sign-language classifier to use. KSL is the only supported
/// vocabulary (ASL support was dropped per product decision — see
/// ml_training/README.md for how the bundled model is produced). Kept as an
/// enum rather than a bare constant so a second sign language can be added
/// later without reshaping the classify() API.
enum SignLanguage { ksl }

extension on SignLanguage {
  String get assetPrefix => switch (this) {
        SignLanguage.ksl => 'ksl_words',
      };
}

class SignClassifierMatch {
  final String label;
  final double confidence;

  const SignClassifierMatch(this.label, this.confidence);
}

class _LoadedModel {
  final Interpreter interpreter;
  final List<String> labels;
  final int outputSize;

  const _LoadedModel(this.interpreter, this.labels, this.outputSize);
}

/// Runs the trained landmark classifier bundled with the app, if present.
/// Bundling is optional — the app works without either model, falling back
/// to the built-in gesture set and Custom Signs. See ml_training/README.md
/// for how these models are produced.
class SignClassifierService {
  SignClassifierService._internal();

  static final SignClassifierService instance = SignClassifierService._internal();

  static const confidenceThreshold = 0.6;

  final Map<SignLanguage, _LoadedModel?> _models = {};

  Future<bool> isAvailable(SignLanguage language) async {
    return (await _load(language)) != null;
  }

  Future<_LoadedModel?> _load(SignLanguage language) async {
    if (_models.containsKey(language)) return _models[language];

    final prefix = language.assetPrefix;
    try {
      final interpreter = await Interpreter.fromAsset('assets/models/${prefix}_model.tflite');
      final labelsJson = await rootBundle.loadString('assets/models/${prefix}_labels.json');
      final labels = (jsonDecode(labelsJson) as List<dynamic>).cast<String>();
      final outputSize = interpreter.getOutputTensor(0).shape.last;
      final model = _LoadedModel(interpreter, labels, outputSize);
      _models[language] = model;
      return model;
    } catch (_) {
      // Model/labels not bundled for this language — not an error, just
      // means this classifier isn't available yet.
      _models[language] = null;
      return null;
    }
  }

  /// Classifies a live hand pose against the trained model for [language].
  /// Returns null if the model isn't bundled, the pose can't be normalized,
  /// or the top prediction is below [confidenceThreshold].
  Future<SignClassifierMatch?> classify(
    List<HandLandmark> landmarks, {
    required SignLanguage language,
  }) async {
    final model = await _load(language);
    if (model == null) return null;

    final vector = HandPoseMatcher.normalizeFrame(landmarks);
    if (vector == null) return null;

    final input = [vector];
    final output = [List<double>.filled(model.outputSize, 0)];
    model.interpreter.run(input, output);

    var bestIndex = 0;
    var bestScore = output[0][0];
    for (var i = 1; i < output[0].length; i++) {
      if (output[0][i] > bestScore) {
        bestScore = output[0][i];
        bestIndex = i;
      }
    }

    if (bestScore < confidenceThreshold || bestIndex >= model.labels.length) return null;
    return SignClassifierMatch(model.labels[bestIndex], bestScore);
  }
}
