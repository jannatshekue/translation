import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay, Brightness;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

import 'sign_classifier_service.dart' show SignLanguage;

enum AppThemeMode { light, dark, automatic }

/// How the user primarily communicates — used to pick sensible accessibility
/// defaults and feature emphasis, never to hide features from anyone.
enum UserProfile { normal, hearingImpaired, speechImpaired }

class SettingsService extends ChangeNotifier {
  SettingsService._internal();

  static final SettingsService instance = SettingsService._internal();

  static const _textScaleKey = 'settings_text_scale';
  static const _highContrastKey = 'settings_high_contrast';
  static const _vibrationKey = 'settings_vibration_enabled';
  static const _flashAlertsKey = 'settings_flash_alerts_enabled';
  static const _themeModeKey = 'settings_theme_mode';
  static const _dayStartMinutesKey = 'settings_day_start_minutes';
  static const _nightStartMinutesKey = 'settings_night_start_minutes';
  static const _userProfileKey = 'settings_user_profile';
  static const _signLanguageKey = 'settings_sign_language';

  double textScale = 1.0;
  bool highContrast = false;
  bool vibrationEnabled = true;
  bool flashAlertsEnabled = false;
  AppThemeMode themeMode = AppThemeMode.automatic;

  /// Null until the user picks one on first run (see onboarding).
  UserProfile? userProfile;

  /// Which trained sign classifier Sign Recognition prefers. Only takes
  /// effect once that language's model is actually bundled (see
  /// ml_training/README.md) — otherwise the screen quietly falls back to
  /// the built-in gesture set and Custom Signs.
  SignLanguage signLanguage = SignLanguage.asl;

  /// Minutes since midnight. Defaults: day starts 6:00 AM, night starts 7:00 PM.
  int dayStartMinutes = 6 * 60;
  int nightStartMinutes = 19 * 60;

  Timer? _autoThemeTimer;

  TimeOfDay get dayStart => TimeOfDay(hour: dayStartMinutes ~/ 60, minute: dayStartMinutes % 60);
  TimeOfDay get nightStart =>
      TimeOfDay(hour: nightStartMinutes ~/ 60, minute: nightStartMinutes % 60);

  /// The brightness the app should actually render, resolving [themeMode]
  /// against the current time when it's [AppThemeMode.automatic].
  Brightness get effectiveBrightness {
    switch (themeMode) {
      case AppThemeMode.light:
        return Brightness.light;
      case AppThemeMode.dark:
        return Brightness.dark;
      case AppThemeMode.automatic:
        final now = DateTime.now();
        final minutesNow = now.hour * 60 + now.minute;
        final isDaytime = dayStartMinutes <= nightStartMinutes
            ? minutesNow >= dayStartMinutes && minutesNow < nightStartMinutes
            : minutesNow >= dayStartMinutes || minutesNow < nightStartMinutes;
        return isDaytime ? Brightness.light : Brightness.dark;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    textScale = prefs.getDouble(_textScaleKey) ?? 1.0;
    highContrast = prefs.getBool(_highContrastKey) ?? false;
    vibrationEnabled = prefs.getBool(_vibrationKey) ?? true;
    flashAlertsEnabled = prefs.getBool(_flashAlertsKey) ?? false;
    themeMode = AppThemeMode.values[prefs.getInt(_themeModeKey) ?? AppThemeMode.automatic.index];
    dayStartMinutes = prefs.getInt(_dayStartMinutesKey) ?? 6 * 60;
    nightStartMinutes = prefs.getInt(_nightStartMinutesKey) ?? 19 * 60;
    final profileIndex = prefs.getInt(_userProfileKey);
    userProfile = profileIndex == null ? null : UserProfile.values[profileIndex];
    signLanguage = SignLanguage.values[prefs.getInt(_signLanguageKey) ?? SignLanguage.asl.index];
    _syncAutoThemeTimer();
    notifyListeners();
  }

  /// Sets the user's profile. On first selection ([applyDefaults] true, the
  /// default), applies one-time accessibility defaults suited to that
  /// profile — it never hides features, only pre-sets toggles the user can
  /// still change freely afterward.
  Future<void> setUserProfile(UserProfile profile, {bool applyDefaults = true}) async {
    userProfile = profile;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userProfileKey, profile.index);

    if (!applyDefaults) return;
    switch (profile) {
      case UserProfile.hearingImpaired:
        await setFlashAlertsEnabled(true);
        await setVibrationEnabled(true);
      case UserProfile.speechImpaired:
        await setVibrationEnabled(true);
      case UserProfile.normal:
        break;
    }
  }

  Future<void> setSignLanguage(SignLanguage value) async {
    signLanguage = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_signLanguageKey, value.index);
  }

  Future<void> setTextScale(double value) async {
    textScale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textScaleKey, value);
  }

  Future<void> setHighContrast(bool value) async {
    highContrast = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_highContrastKey, value);
  }

  Future<void> setVibrationEnabled(bool value) async {
    vibrationEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vibrationKey, value);
  }

  Future<void> setFlashAlertsEnabled(bool value) async {
    flashAlertsEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_flashAlertsKey, value);
  }

  /// Light tap feedback for routine taps (list items, toggles, tab changes).
  void hapticTap() {
    if (vibrationEnabled) HapticFeedback.selectionClick();
  }

  /// Medium feedback for a meaningful action completing (save, recognition).
  void hapticImpact() {
    if (vibrationEnabled) HapticFeedback.mediumImpact();
  }

  /// Strong feedback for a significant event (emergency alert sent).
  void hapticSuccess() {
    if (vibrationEnabled) HapticFeedback.heavyImpact();
  }

  Future<void> setThemeMode(AppThemeMode value) async {
    themeMode = value;
    _syncAutoThemeTimer();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, value.index);
  }

  Future<void> setDayStart(TimeOfDay time) async {
    dayStartMinutes = time.hour * 60 + time.minute;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dayStartMinutesKey, dayStartMinutes);
  }

  Future<void> setNightStart(TimeOfDay time) async {
    nightStartMinutes = time.hour * 60 + time.minute;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_nightStartMinutesKey, nightStartMinutes);
  }

  /// Ticks once a minute while in automatic mode so the UI updates live if
  /// the app is left open across a day/night boundary.
  void _syncAutoThemeTimer() {
    _autoThemeTimer?.cancel();
    _autoThemeTimer = null;
    if (themeMode == AppThemeMode.automatic) {
      _autoThemeTimer = Timer.periodic(const Duration(minutes: 1), (_) => notifyListeners());
    }
  }

  @override
  void dispose() {
    _autoThemeTimer?.cancel();
    super.dispose();
  }
}
