import 'package:flutter/material.dart';

/// The app's design system. Every colour, radius and component style lives
/// here so screens inherit one consistent look instead of styling themselves.
///
/// Direction: classic and professional — a deep navy primary with a calm
/// teal accent on a quiet off-white canvas, flat bordered cards instead of
/// drop shadows, generous spacing, and red reserved strictly for emergencies.
class AppTheme {
  AppTheme._();

  // Brand
  static const Color navy = Color(0xFF233E8B);
  static const Color navyDeep = Color(0xFF16275C);
  static const Color teal = Color(0xFF0F766E);

  /// Red is reserved for emergencies and destructive actions only.
  static const Color emergency = Color(0xFFC62828);
  static const Color emergencyDeep = Color(0xFF8E1B1B);
  static const Color success = Color(0xFF2E7D32);

  // Spacing / shape tokens shared by screens.
  static const double screenPadding = 20;
  static const double radiusCard = 20;
  static const double radiusControl = 14;

  /// The signature gradient used on hero surfaces.
  static LinearGradient heroGradient(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? const [Color(0xFF2B4BA8), Color(0xFF1B2F6E)]
          : const [navy, navyDeep],
    );
  }

  static ThemeData light({bool highContrast = false}) => _build(
        brightness: Brightness.light,
        highContrast: highContrast,
      );

  static ThemeData dark({bool highContrast = false}) => _build(
        brightness: Brightness.dark,
        highContrast: highContrast,
      );

  static ThemeData _build({required Brightness brightness, required bool highContrast}) {
    final isDark = brightness == Brightness.dark;

    final ColorScheme scheme;
    if (highContrast) {
      scheme = isDark ? const ColorScheme.highContrastDark() : const ColorScheme.highContrastLight();
    } else {
      final seeded = ColorScheme.fromSeed(
        seedColor: navy,
        brightness: brightness,
      );
      scheme = isDark
          ? seeded.copyWith(
              primary: const Color(0xFF9DB4FF),
              onPrimary: const Color(0xFF0C1A45),
              primaryContainer: const Color(0xFF263A7A),
              onPrimaryContainer: const Color(0xFFDCE4FF),
              secondary: const Color(0xFF6FD3C9),
              surface: const Color(0xFF161C2E),
              surfaceContainerLowest: const Color(0xFF0E1322),
              surfaceContainerLow: const Color(0xFF1A2135),
              surfaceContainer: const Color(0xFF1D2438),
              surfaceContainerHigh: const Color(0xFF242C42),
              surfaceContainerHighest: const Color(0xFF2B344D),
              outlineVariant: const Color(0xFF2F3954),
              error: const Color(0xFFFF8A80),
            )
          : seeded.copyWith(
              primary: navy,
              onPrimary: Colors.white,
              primaryContainer: const Color(0xFFDDE5FB),
              onPrimaryContainer: navyDeep,
              secondary: teal,
              surface: Colors.white,
              surfaceContainerLowest: const Color(0xFFF4F6FB),
              surfaceContainerLow: const Color(0xFFF8F9FD),
              surfaceContainer: const Color(0xFFEFF1F8),
              surfaceContainerHigh: const Color(0xFFE8EBF4),
              surfaceContainerHighest: const Color(0xFFE2E6F1),
              outlineVariant: const Color(0xFFDCE0EC),
              error: emergency,
            );
    }

    final canvas = scheme.surfaceContainerLowest;
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
    );
    final text = base.textTheme;

    final textTheme = text.copyWith(
      displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w500),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.1),
      bodyLarge: text.bodyLarge?.copyWith(height: 1.4),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.4),
    );

    final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl));

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: canvas,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: controlShape,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: controlShape),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        // A fixed 12sp with no extra letter spacing, so "Communicate" fits in
        // the quarter-width each tab gets even on a 360dp-wide phone.
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            fontSize: 12,
            letterSpacing: 0,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? scheme.surfaceContainerHighest : const Color(0xFF1B2236),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surface,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: controlShape,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: scheme.surfaceContainerHigh,
        circularTrackColor: scheme.surfaceContainerHigh,
      ),
    );
  }
}
