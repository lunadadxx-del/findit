import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/app_language.dart';
import '../models/target_objects.dart';
import 'localization_service.dart';
import 'settings_service.dart';

enum AssistantIntent {
  findObject,
  describeSurroundings,
  helpMeUnderstand,
  settings,
  help,
  lostPhone,
  irisWakeup,
  unknown,
}

class IntentResult {
  const IntentResult({
    required this.intent,
    this.target,
    this.spokenReply,
    this.isUnsupported = false,
  });

  final AssistantIntent intent;
  final String? target;
  final String? spokenReply;
  final bool isUnsupported;
}

/// Conversational intelligence and intent parsing layer per PRD Section 19 & 20.
///
/// Principles:
/// - NEVER runs inside the real-time camera guidance loop.
/// - Offline-first: Full local keyword & regex intent parsing for instant response with zero network.
/// - Optional Cloud AI (Gemini): Used only when explicitly enabled by user in Settings for complex natural-language phrasing.
class AssistantService {
  AssistantService._();
  static final AssistantService instance = AssistantService._();

  GenerativeModel? _model;
  String? _lastApiKey;

  GenerativeModel? _getModel() {
    final key = SettingsService.instance.geminiApiKey;
    if (key.isEmpty) return null;
    if (_model == null || _lastApiKey != key) {
      _lastApiKey = key;
      _model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: key);
    }
    return _model;
  }

  /// Parses user voice or text input into an actionable FindIt intent.
  Future<IntentResult> processUserInput(
    String transcript, {
    AppLanguage? language,
  }) async {
    final text = transcript.trim();
    if (text.isEmpty) {
      return const IntentResult(intent: AssistantIntent.unknown);
    }

    final lang = language ?? SettingsService.instance.preferredLanguage;
    final l10n = LocalizationService.instance;
    final lower = text.toLowerCase();

    // 1. Check for alarm / lost phone mode intent ONLY when user explicitly asks where phone is
    final isAlarmQuery = lower.contains('where are you') ||
        lower.contains('where is my phone') ||
        lower.contains('where is the phone') ||
        lower.contains('find my phone') ||
        lower.contains('ring my phone') ||
        lower.contains('ring the phone') ||
        lower.contains('lost phone') ||
        lower.contains('lost mode') ||
        lower.contains('खोया फोन') ||
        lower.contains('कहाँ हो') ||
        lower.contains('कहा हो') ||
        lower.contains('फोन ढूंढो') ||
        lower.contains('फोन बजाओ') ||
        lower.contains('ಫೋನ್ ಎಲ್ಲಿದೆ') ||
        lower.contains('ಎಲ್ಲಿದ್ದೀಯ') ||
        lower.contains('ಕಳೆದುಹೋದ ಫೋನ್');

    if (isAlarmQuery) {
      return const IntentResult(intent: AssistantIntent.lostPhone);
    }

    // 2. Strip "Hey Iris" hotword prefix if present
    var cleanQuery = text;
    final irisPrefixRegex = RegExp(
      r'^(hey\s+|hi\s+|ok\s+|okay\s+|here\s+|hay\s+)?(iris|irish|ayres|aires|airis|ayris|eris|harris|harry|heiress|high\s*risk|it\s+is)\b[:,\s]*',
      caseSensitive: false,
    );
    if (irisPrefixRegex.hasMatch(cleanQuery)) {
      cleanQuery = cleanQuery.replaceFirst(irisPrefixRegex, '').trim();
    }
    final hindiPrefixRegex = RegExp(r'^(हे|हाय|हेलो\s+)?(आइरिस|आयरिस|आईरिस|इरिस)\b[:,\s]*', caseSensitive: false);
    if (hindiPrefixRegex.hasMatch(cleanQuery)) {
      cleanQuery = cleanQuery.replaceFirst(hindiPrefixRegex, '').trim();
    }
    final kannadaPrefixRegex = RegExp(r'^(ಹೇ|ಹಾಯ್\s+)?(ಐರಿಸ್)\b[:,\s]*');
    if (kannadaPrefixRegex.hasMatch(cleanQuery)) {
      cleanQuery = cleanQuery.replaceFirst(kannadaPrefixRegex, '').trim();
    }

    // If only "Hey Iris" was spoken -> Assistant Wakeup
    if (cleanQuery.isEmpty) {
      return IntentResult(
        intent: AssistantIntent.irisWakeup,
        spokenReply: l10n.howCanIHelp(lang),
      );
    }

    // 3. Check for explicitly unsupported targets ("find my keys", "चश्मा")
    if (TargetObjects.isQueryUnsupported(cleanQuery)) {
      return IntentResult(
        intent: AssistantIntent.findObject,
        isUnsupported: true,
        spokenReply: l10n.unsupportedObject(lang),
      );
    }

    // 4. Fast local matching (100% offline, immediate)
    final matchedTarget = TargetObjects.matchVoiceInput(cleanQuery);
    if (matchedTarget != null) {
      return IntentResult(
        intent: AssistantIntent.findObject,
        target: matchedTarget,
        spokenReply: l10n.searchingTarget(matchedTarget, lang),
      );
    }

    // Check for surroundings description intent
    if (lower.contains('surrounding') ||
        lower.contains('around me') ||
        lower.contains('आस-पास') ||
        lower.contains('ಸುತ್ತಮುತ್ತ') ||
        lower.contains('పరిసరాలు') ||
        lower.contains('சுற்றம்')) {
      return const IntentResult(intent: AssistantIntent.describeSurroundings);
    }

    // Check for settings intent
    if (lower.contains('setting') ||
        lower.contains('सेटिंग') ||
        lower.contains('ಸೆಟ್ಟಿಂಗ್') ||
        lower.contains('సెట్టింగ్') ||
        lower.contains('அமைப்பு')) {
      return const IntentResult(intent: AssistantIntent.settings);
    }

    // Check for help intent
    if (lower.contains('help') ||
        lower.contains('मदद') ||
        lower.contains('ಸಹಾಯ') ||
        lower.contains('సహాయం') ||
        lower.contains('உதவி')) {
      return const IntentResult(intent: AssistantIntent.help);
    }

    // 3. Optional Cloud AI (Gemini) fallback if enabled and connected
    final settings = SettingsService.instance;
    if (settings.cloudAiEnabled && settings.geminiApiKey.isNotEmpty) {
      try {
        final model = _getModel();
        if (model != null) {
          final prompt =
              '''
You are the conversational intent parser for FindIt, an accessibility app for blind users.
Supported target objects: bottle, phone, cup, book, bag, backpack, remote, keyboard, mouse, laptop.
Unsupported objects: keys, wallet, glasses, watch.

User input: "$text"

Respond ONLY with valid JSON in this format:
{"intent": "FIND_OBJECT" | "DESCRIBE_SURROUNDINGS" | "HELP" | "CHAT", "target": "bottle" | null, "reply": "short spoken response in ${lang.englishName}"}
''';
          final response = await model.generateContent([Content.text(prompt)]);
          final raw = response.text ?? '';
          if (raw.contains('FIND_OBJECT') && raw.contains('target')) {
            for (final key in TargetObjects.supported.keys) {
              if (raw.toLowerCase().contains(key)) {
                return IntentResult(
                  intent: AssistantIntent.findObject,
                  target: key,
                  spokenReply: l10n.searchingTarget(key, lang),
                );
              }
            }
          }
        }
      } catch (_) {
        // Fall back gracefully to local unknown result
      }
    }

    final unknownMsg = switch (lang) {
      AppLanguage.hindi => 'मुझे समझ नहीं आया। कृपया खोजने के लिए कोई वस्तु बताएं, जैसे बोतल, फोन, या कप।',
      AppLanguage.kannada => 'ನನಗೆ ಅರ್ಥವಾಗಲಿಲ್ಲ. ದಯವಿಟ್ಟು ಬಾಟಲ್, ಫೋನ್ ಅಥವಾ ಕಪ್ ಎಂದು ಹೇಳಿ.',
      AppLanguage.telugu => 'నాకు అర్థం కాలేదు. దయచేసి బాటిల్, ఫోన్ లేదా కప్పు అని చెప్పండి.',
      AppLanguage.tamil => 'எனக்கு புரியவில்லை. தயவுசெய்து பாட்டில், போன் அல்லது கப் என்று சொல்லுங்கள்.',
      _ => 'I did not catch that. Please say an object to find, like bottle, phone, or cup.',
    };
    return IntentResult(
      intent: AssistantIntent.unknown,
      spokenReply: unknownMsg,
    );
  }
}
