import 'package:findit/models/app_language.dart';
import 'package:findit/services/assistant_service.dart';
import 'package:findit/services/lost_phone_service.dart';
import 'package:findit/services/speech_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssistantService Offline Intent Parsing', () {
    test('extracts direct object finding intent', () async {
      final res = await AssistantService.instance.processUserInput(
        'find my bottle',
      );
      expect(res.intent, AssistantIntent.findObject);
      expect(res.target, 'bottle');
      expect(res.isUnsupported, isFalse);
    });

    test('extracts multilingual object finding intent in Hindi', () async {
      final res = await AssistantService.instance.processUserInput(
        'मेरी बोतल ढूंढो',
        language: AppLanguage.hindi,
      );
      expect(res.intent, AssistantIntent.findObject);
      expect(res.target, 'bottle');
      expect(res.spokenReply, contains('बोतल'));
    });

    test('extracts multilingual object finding intent in Kannada', () async {
      final res = await AssistantService.instance.processUserInput(
        'ನನ್ನ ಫೋನ್ ಹುಡುಕಿ',
        language: AppLanguage.kannada,
      );
      expect(res.intent, AssistantIntent.findObject);
      expect(res.target, 'phone');
    });

    test('flags unsupported objects honestly without faking', () async {
      final res = await AssistantService.instance.processUserInput(
        'find my keys',
      );
      expect(res.isUnsupported, isTrue);
      expect(
        res.spokenReply,
        contains("I can't reliably find that object yet"),
      );
    });

    test('flags unsupported objects in Hindi honestly', () async {
      final res = await AssistantService.instance.processUserInput(
        'मेरी चाबी ढूंढो',
        language: AppLanguage.hindi,
      );
      expect(res.isUnsupported, isTrue);
      expect(res.spokenReply, contains('भरोसेमंद तरीके से नहीं ढूंढ सकता'));
    });

    test('extracts surroundings intent', () async {
      final res = await AssistantService.instance.processUserInput(
        'what is around me',
      );
      expect(res.intent, AssistantIntent.describeSurroundings);
    });

    test('extracts settings intent', () async {
      final res = await AssistantService.instance.processUserInput(
        'open settings',
      );
      expect(res.intent, AssistantIntent.settings);
    });

    test('extracts help intent', () async {
      final res = await AssistantService.instance.processUserInput(
        'i need help',
      );
      expect(res.intent, AssistantIntent.help);
    });

    test('extracts lost phone mode intent', () async {
      final res = await AssistantService.instance.processUserInput(
        'enable lost phone mode',
      );
      expect(res.intent, AssistantIntent.lostPhone);
    });

    test('extracts hey iris wakeup intent without where are you', () async {
      final res = await AssistantService.instance.processUserInput(
        'hey iris',
      );
      expect(res.intent, AssistantIntent.irisWakeup);
      expect(res.spokenReply, isNotNull);
    });

    test('extracts hey iris with direct object search', () async {
      final res = await AssistantService.instance.processUserInput(
        'hey iris find my bottle',
      );
      expect(res.intent, AssistantIntent.findObject);
      expect(res.target, 'bottle');
    });

    test('extracts hey iris where are you as lost phone alarm intent', () async {
      final res = await AssistantService.instance.processUserInput(
        'hey iris where are you',
      );
      expect(res.intent, AssistantIntent.lostPhone);
    });

    test('extracts lost phone intent in Hindi', () async {
      final res = await AssistantService.instance.processUserInput(
        'मेरा खोया फोन ढूंढो',
        language: AppLanguage.hindi,
      );
      expect(res.intent, AssistantIntent.lostPhone);
    });

    test('returns unknown for unrecognizable query', () async {
      final res = await AssistantService.instance.processUserInput(
        'sing a song for me',
      );
      expect(res.intent, AssistantIntent.unknown);
    });
  });

  group('LostPhoneService State Contracts', () {
    test('initial state has microphone off and alarm silent', () {
      final service = LostPhoneService.instance;
      expect(service.isRunning, isFalse);
      expect(service.isAlarmRinging, isFalse);
      expect(service.triggeredPhrase, isNull);
      expect(service.lastError, isNull);
    });
  });

  group('SpeechService Language Contract & Fallback Models', () {
    test('LanguageSwitchResult model stores supported state properly', () {
      const res = LanguageSwitchResult(
        targetLanguage: AppLanguage.kannada,
        activeLanguage: AppLanguage.kannada,
        isSupported: true,
      );
      expect(res.isSupported, isTrue);
      expect(res.targetLanguage, AppLanguage.kannada);
      expect(res.activeLanguage, AppLanguage.kannada);
      expect(res.fallbackReason, isNull);
    });

    test('LanguageSwitchResult model stores fallback state and reason properly', () {
      const res = LanguageSwitchResult(
        targetLanguage: AppLanguage.hindi,
        activeLanguage: AppLanguage.english,
        isSupported: false,
        fallbackReason: 'Hindi voice is not installed on this device.',
      );
      expect(res.isSupported, isFalse);
      expect(res.targetLanguage, AppLanguage.hindi);
      expect(res.activeLanguage, AppLanguage.english);
      expect(res.fallbackReason, contains('Hindi voice is not installed'));
    });

    test('SpeechService defaults before initialization', () {
      final service = SpeechService();
      expect(service.isReady, isFalse);
      expect(service.isSpeaking, isFalse);
      expect(service.currentLanguage, AppLanguage.english);
    });
  });
}
