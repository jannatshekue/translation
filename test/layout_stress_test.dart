import 'dart:io';

import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translation/core/profile/app_tools.dart';
import 'package:translation/core/services/settings_service.dart';
import 'package:translation/main.dart';
import 'package:translation/routes/app_routes.dart';

/// Layout regression guard: the largest text size the Settings slider allows
/// (160%), on a small 360x640 phone, in light/dark and high contrast, for
/// every profile. Any "RenderFlex overflowed" or other layout error fails.
String stage = 'start';

void main() {
  // Real glyph widths matter for wrapping, so load the bundled fonts instead
  // of the test framework's square placeholder font.
  setUpAll(() async {
    Future<ByteData> bytes(String path) async => ByteData.sublistView(await File(path).readAsBytes());
    final roboto = FontLoader('Roboto')
      ..addFont(bytes('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(bytes('assets/fonts/Roboto-Medium.ttf'))
      ..addFont(bytes('assets/fonts/Roboto-Bold.ttf'))
      ..addFont(bytes('assets/fonts/Roboto-Black.ttf'));
    await roboto.load();
    await (FontLoader('Parisienne')..addFont(bytes('assets/fonts/Parisienne-Regular.ttf'))).load();
  });

  // Plugins that don't exist in the test VM answer with empty results so
  // screens that ask them for locales/voices can still be laid out.
  void mockPlugins() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in const [
      'plugin.csdcorp.com/speech_to_text',
      'flutter_tts',
      'translation/emergency_sms',
      'translation/contacts',
      'flutter.baseflow.com/permissions/methods',
      'flutter.baseflow.com/geolocator',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        if (call.method == 'getLanguages' || call.method == 'locales') return <dynamic>[];
        if (call.method == 'checkPermissionStatus') return 0;
        if (call.method == 'requestPermissions') {
          return {for (final p in (call.arguments as List)) p as int: 0};
        }
        return null;
      });
    }
  }

  Future<List<String>> pumpAndCollect(
    WidgetTester tester, {
    required UserProfile profile,
    required bool dark,
    required bool highContrast,
    required Future<void> Function() body,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService.instance;
    settings.userProfile = profile;
    settings.textScale = 1.6;
    settings.highContrast = highContrast;
    settings.themeMode = dark ? AppThemeMode.dark : AppThemeMode.light;

    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;

    // Run as Android so Emergency shows its real layout (the SOS button)
    // rather than the "Android only" notice. Reset in the finally block: the
    // framework fails any test that ends with a debug override still set.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final problems = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed') || text.contains('RenderFlex') || text.contains('constraints')) {
        // Which screen, and the widget that caused it, so a failure is actionable.
        final where = RegExp(r'file:///[^\s]*lib/[^\s]*').firstMatch(details.toString())?.group(0) ?? '';
        problems.add('[$stage] ${text.split('\n').first} $where');
      }
    };
    try {
      await body();
    } finally {
      FlutterError.onError = original;
      debugDefaultTargetPlatformOverride = null;
    }
    return problems;
  }

  Future<void> openApp(WidgetTester tester) async {
    await tester.pumpWidget(const TranslationApp());
    await tester.pump(const Duration(milliseconds: 4700));
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> push(WidgetTester tester, String route, {Object? args}) async {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pushNamed(route, arguments: args);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Scrolls the visible list to its end, so lazily-built items further down
  /// are laid out (and checked) too.
  Future<void> scrollThrough(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable).hitTestable();
    if (scrollable.evaluate().isEmpty) return;
    for (var i = 0; i < 14; i++) {
      await tester.drag(scrollable.first, const Offset(0, -260), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> scrollToTop(WidgetTester tester) async {
    final scrollable = find.byType(Scrollable).hitTestable();
    if (scrollable.evaluate().isEmpty) return;
    for (var i = 0; i < 14; i++) {
      await tester.drag(scrollable.first, const Offset(0, 260), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> pop(WidgetTester tester) async {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await tester.pump(const Duration(milliseconds: 600));
  }

  for (final profile in UserProfile.values) {
    for (final dark in [false, true]) {
      for (final highContrast in [false, true]) {
        final name = '${profile.name} dark=$dark highContrast=$highContrast';
        testWidgets('no layout overflow at 160% text: $name', (tester) async {
          mockPlugins();
          final problems = await pumpAndCollect(
            tester,
            profile: profile,
            dark: dark,
            highContrast: highContrast,
            body: () async {
              stage = 'home';
              await openApp(tester);

              // The four tabs.
              for (final label in ['Communicate', 'Learn', 'Emergency', 'Home']) {
                stage = 'tab $label';
                await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
                // Two ticks: the first builds the tab, the second lets tabs
                // that read saved settings (Emergency) finish loading.
                await tester.pump(const Duration(milliseconds: 600));
                await tester.pump(const Duration(milliseconds: 600));

                // Not an exception, but just as broken: a tab label that
                // breaks mid-word onto a second line.
                final navLabel = find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
                final labelHeight = tester.getSize(navLabel).height;
                expect(labelHeight, lessThan(32), reason: 'tab label "$label" wrapped onto several lines');

                if (label == 'Emergency') {
                  // The SOS mark must stay on one line inside its disc.
                  await scrollToTop(tester);
                  expect(find.text('SOS'), findsOneWidget);
                  final sosHeight = tester.getSize(find.text('SOS')).height;
                  expect(sosHeight, lessThan(70), reason: '"SOS" wrapped onto several lines');
                }
                await scrollThrough(tester);
              }

              // The profile chooser bottom sheet, opened from Home's pill.
              stage = 'profile sheet';
              await scrollToTop(tester);
              await tester.tap(find.byIcon(Icons.expand_more));
              await tester.pump(const Duration(milliseconds: 600));
              expect(find.text('How do you communicate?'), findsOneWidget);
              await scrollThrough(tester);
              await tester.tapAt(const Offset(180, 20)); // dismiss on the scrim
              await tester.pump(const Duration(milliseconds: 600));

              // Full-screen destinations.
              stage = 'settings';
              await push(tester, AppRoutes.settings);
              expect(find.text('Settings'), findsWidgets);
              await scrollThrough(tester);
              expect(find.text('Backup & restore'), findsOneWidget);
              await pop(tester);
              stage = 'voice listen';
              await push(tester, AppRoutes.voiceTranslation,
                  args: const VoiceScreenArgs(mode: VoiceMode.listen));
              expect(find.text('Speech & text'), findsOneWidget);
              await scrollThrough(tester);
              await pop(tester);
              stage = 'voice speak';
              await push(tester, AppRoutes.voiceTranslation,
                  args: const VoiceScreenArgs(mode: VoiceMode.speak));
              await pop(tester);
              stage = 'conversation';
              await push(tester, AppRoutes.conversationMode);
              expect(find.text('Conversation mode'), findsWidgets);
              await scrollThrough(tester);
              await pop(tester);
              stage = 'connect devices';
              await push(tester, AppRoutes.deviceSync);
              expect(find.text('Connect devices'), findsWidgets);
              await scrollThrough(tester);
              await pop(tester);
            },
          );
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      }
    }
  }

  for (final dark in [false, true]) {
    testWidgets('onboarding has no layout overflow at 160% text (dark=$dark)', (tester) async {
      mockPlugins();
      final problems = await pumpAndCollect(
        tester,
        profile: UserProfile.normal,
        dark: dark,
        highContrast: false,
        body: () async {
          // First run: no profile chosen yet.
          SettingsService.instance.userProfile = null;
          stage = 'onboarding';
          await tester.pumpWidget(const TranslationApp());
          await tester.pump(const Duration(milliseconds: 4700));
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.text('How do you communicate?'), findsOneWidget);
          for (final label in ['Hearing & speaking', 'Deaf or hard of hearing', 'Cannot speak']) {
            await scrollToTop(tester);
            await tester.scrollUntilVisible(
              find.text(label),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.tap(find.text(label));
            await tester.pump(const Duration(milliseconds: 400));
            await scrollThrough(tester);
          }
        },
      );
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}
