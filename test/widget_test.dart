import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translation/core/services/settings_service.dart';
import 'package:translation/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    // Each test's profile choice shouldn't leak into the next test.
    SettingsService.instance.userProfile = null;
  });

  testWidgets('First run goes through the splash screen to profile selection',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TranslationApp());

    expect(find.text('See it. Say it. Understand each other.'), findsOneWidget);

    // The splash screen navigates away via Future.delayed, not an animation,
    // so advance the fake clock past it rather than using pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pump();

    expect(find.text('How would you like the\napp to work for you?'), findsOneWidget);

    await tester.tap(find.text('Hearing & speaking'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Sign & Voice Translator'), findsOneWidget);
    expect(find.text('Sign Recognition'), findsOneWidget);
  });

  testWidgets('Returning user with a profile already set skips onboarding',
      (WidgetTester tester) async {
    SettingsService.instance.userProfile = UserProfile.normal;

    await tester.pumpWidget(const TranslationApp());
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pump();

    expect(find.text('Sign & Voice Translator'), findsOneWidget);
    expect(find.text('Sign Recognition'), findsOneWidget);
  });
}
