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

    // The tagline is typed out, so it is exposed as one semantic label.
    expect(find.bySemanticsLabel('Clear. Instant. Inclusive.'), findsOneWidget);

    // The splash screen navigates away via Future.delayed, not an animation,
    // so advance the fake clock past it rather than using pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 4700));
    await tester.pump();

    expect(find.text('How do you communicate?'), findsOneWidget);

    // Continue stays disabled until a profile is chosen.
    await tester.tap(find.text('Hearing & speaking'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Sign & Voice Translator'), findsOneWidget);
    expect(find.text('Start a conversation'), findsOneWidget);
  });

  testWidgets('Returning user with a profile already set skips onboarding',
      (WidgetTester tester) async {
    SettingsService.instance.userProfile = UserProfile.normal;

    await tester.pumpWidget(const TranslationApp());
    await tester.pump(const Duration(milliseconds: 4700));
    await tester.pump();

    expect(find.text('Sign & Voice Translator'), findsOneWidget);
    expect(find.text('Start a conversation'), findsOneWidget);
  });

  testWidgets('The hero action on Home depends on the profile', (WidgetTester tester) async {
    SettingsService.instance.userProfile = UserProfile.hearingImpaired;
    await tester.pumpWidget(const TranslationApp());
    await tester.pump(const Duration(milliseconds: 4700));
    await tester.pump();
    expect(find.text('Live captions'), findsWidgets);
    expect(find.text('Start a conversation'), findsNothing);

    SettingsService.instance.userProfile = UserProfile.speechImpaired;
    await tester.pumpWidget(const TranslationApp());
    await tester.pump(const Duration(milliseconds: 4700));
    await tester.pump();
    expect(find.text('Speak for me'), findsOneWidget);
  });
}
