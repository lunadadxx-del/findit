import 'package:findit/models/app_language.dart';
import 'package:findit/screens/language_selection_screen.dart';
import 'package:findit/services/settings_service.dart';
import 'package:findit/services/volume_key_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.initialize();
  });

  group('VolumeKeyService Unit Tests', () {
    test('VolumeKeyService emits events through stream', () async {
      final service = VolumeKeyService.instance;
      final events = <VolumeKeyEvent>[];
      final sub = service.events.listen(events.add);

      service.emitSyntheticEvent(VolumeKeyEventType.up, detail: 'test_up');
      service.emitSyntheticEvent(VolumeKeyEventType.down, detail: 'test_down');
      service.emitSyntheticEvent(VolumeKeyEventType.confirm, detail: 'both_volume_keys');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.length, 3);
      expect(events[0].type, VolumeKeyEventType.up);
      expect(events[0].detail, 'test_up');
      expect(events[1].type, VolumeKeyEventType.down);
      expect(events[1].detail, 'test_down');
      expect(events[2].type, VolumeKeyEventType.confirm);
      expect(events[2].detail, 'both_volume_keys');

      await sub.cancel();
    });
  });

  group('LanguageSelectionScreen Widget Tests', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.findit.findit/volume_keys'),
        (call) async => true,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => 1,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('vibration'),
        (call) async => true,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.findit.findit/volume_keys'),
        null,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        null,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('vibration'),
        null,
      );
    });

    testWidgets('renders all 3 required language options (English, Hindi, Kannada)',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: LanguageSelectionScreen(isFirstLaunch: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Check language card texts
      expect(find.text('English'), findsOneWidget);
      expect(find.text('हिंदी'), findsOneWidget);
      expect(find.text('ಕನ್ನಡ'), findsOneWidget);

      // Check header and instructions
      expect(find.textContaining('VOICE & VOLUME CONTROL'), findsOneWidget);
      expect(find.text('REPLAY'), findsOneWidget);
    });

    testWidgets('cycles options via VolumeKeyService and updates selection',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: LanguageSelectionScreen(isFirstLaunch: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Initial selection is English
      expect(find.text('CONFIRM ENGLISH'), findsOneWidget);

      // Emit volume up to cycle to Hindi
      VolumeKeyService.instance.emitSyntheticEvent(VolumeKeyEventType.up);
      await tester.pump(const Duration(milliseconds: 100));

      // Selection changes to Hindi
      expect(find.text('CONFIRM HINDI'), findsOneWidget);

      // Cycle again to Kannada
      VolumeKeyService.instance.emitSyntheticEvent(VolumeKeyEventType.up);
      await tester.pump(const Duration(milliseconds: 100));

      // Selection changes to Kannada
      expect(find.text('CONFIRM KANNADA'), findsOneWidget);
    });

    testWidgets('confirming selection updates SettingsService preference',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: LanguageSelectionScreen(isFirstLaunch: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Cycle to Hindi
      VolumeKeyService.instance.emitSyntheticEvent(VolumeKeyEventType.up);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('CONFIRM HINDI'), findsOneWidget);

      // Emit confirm event
      VolumeKeyService.instance.emitSyntheticEvent(
        VolumeKeyEventType.confirm,
        detail: 'both_volume_keys',
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(SettingsService.instance.preferredLanguage, AppLanguage.hindi);
      expect(SettingsService.instance.isFirstLaunch, false);
    });

    testWidgets('circular navigation wraps from first to last and last to first',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: LanguageSelectionScreen(isFirstLaunch: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Initial selection: English
      expect(find.text('CONFIRM ENGLISH'), findsOneWidget);

      // Volume Down moves backwards: wraps around from English (0) to Kannada (2)
      VolumeKeyService.instance.emitSyntheticEvent(VolumeKeyEventType.down);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('CONFIRM KANNADA'), findsOneWidget);

      // Wait past debounce (200ms)
      await tester.pump(const Duration(milliseconds: 250));

      // Volume Up moves forwards: wraps around from Kannada (2) to English (0)
      VolumeKeyService.instance.emitSyntheticEvent(VolumeKeyEventType.up);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('CONFIRM ENGLISH'), findsOneWidget);
    });

    testWidgets('confirming selection via power button detail updates SettingsService',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: LanguageSelectionScreen(isFirstLaunch: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Cycle to Hindi
      VolumeKeyService.instance.emitSyntheticEvent(VolumeKeyEventType.up);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('CONFIRM HINDI'), findsOneWidget);

      // Emit confirm event with power_button detail
      VolumeKeyService.instance.emitSyntheticEvent(
        VolumeKeyEventType.confirm,
        detail: 'power_button',
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(SettingsService.instance.preferredLanguage, AppLanguage.hindi);
    });
  });
}
