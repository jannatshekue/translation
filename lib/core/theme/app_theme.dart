import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light({bool highContrast = false}) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: highContrast
            ? const ColorScheme.highContrastLight()
            : ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      );

  static ThemeData dark({bool highContrast = false}) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: highContrast
            ? const ColorScheme.highContrastDark()
            : ColorScheme.fromSeed(
                seedColor: Colors.deepPurple,
                brightness: Brightness.dark,
              ),
      );
}
