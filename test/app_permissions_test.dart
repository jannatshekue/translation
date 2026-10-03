import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:translation/core/utils/app_permissions.dart';

/// The permission rules:
///  * only Android's own prompt — the app shows no explanation box of its own;
///  * a refusal is final for that attempt: a short message, no second box,
///    no Settings page, no re-asking.
void main() {
  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  late List<String> calls;
  late PermissionStatus current; // what Android reports right now
  late PermissionStatus onRequest; // what the person answers to Android's prompt

  setUp(() {
    calls = [];
    current = PermissionStatus.denied;
    onRequest = PermissionStatus.denied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'checkPermissionStatus':
          return current.index;
        case 'requestPermissions':
          current = onRequest;
          return {for (final p in (call.arguments as List)) p as int: onRequest.index};
        case 'openAppSettings':
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<bool> ask(WidgetTester tester, {bool announce = true}) async {
    late bool result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await AppPermissions.ensure(context, Permission.camera, announceDenial: announce);
              },
              child: const Text('use camera'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('use camera'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return result;
  }

  testWidgets('already allowed: nothing is asked and nothing is shown', (tester) async {
    current = PermissionStatus.granted;

    final granted = await ask(tester);

    expect(granted, isTrue);
    expect(calls, isNot(contains('requestPermissions')));
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the app never puts up its own explanation box before Android asks', (tester) async {
    onRequest = PermissionStatus.granted;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => AppPermissions.ensure(context, Permission.camera),
            child: const Text('use camera'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('use camera'));
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('allowing in Android\'s prompt lets the feature run, with no message', (tester) async {
    onRequest = PermissionStatus.granted;

    final granted = await ask(tester);

    expect(granted, isTrue);
    expect(calls.where((c) => c == 'requestPermissions'), hasLength(1));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('refusing is final: short message, no box, no Settings, no second ask', (tester) async {
    onRequest = PermissionStatus.denied;

    final granted = await ask(tester);

    expect(granted, isFalse);
    expect(find.text('Camera permission is needed for this feature.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls, isNot(contains('openAppSettings')));
    expect(calls.where((c) => c == 'requestPermissions'), hasLength(1));
  });

  testWidgets('a screen that shows its own message can switch the pop-up message off', (tester) async {
    final granted = await ask(tester, announce: false);

    expect(granted, isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('trying the feature again asks again (only on use)', (tester) async {
    await ask(tester);
    await tester.tap(find.text('use camera'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(calls.where((c) => c == 'requestPermissions'), hasLength(2));
  });

  test('messages name the permission', () {
    expect(AppPermissions.neededMessage(Permission.camera), 'Camera permission is needed for this feature.');
    expect(AppPermissions.neededMessage(Permission.microphone), 'Microphone permission is needed for this feature.');
    expect(AppPermissions.neededMessage(Permission.sms), 'SMS permission is needed for this feature.');
    expect(AppPermissions.neededMessage(Permission.bluetoothScan), 'Nearby devices permission is needed for this feature.');
  });
}
