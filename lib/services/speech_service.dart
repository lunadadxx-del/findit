import 'package:flutter_tts/flutter_tts.dart';
import '../models/app_language.dart';
import 'settings_service.dart';

/// Central Voice Guidance Manager conforming to PRD Section 15 & 22.
///
/// Controls:
/// - Speech priority (urgent found/stop messages bypass cooldown and interrupt)
/// - Speech cooldown (never repeats the same instruction without cooldown)
/// - Movement / zone change responsiveness
/// - Dynamic language switching (English, Hindi, Kannada, Telugu, Tamil)
/// - Voice speed & pitch
/// - Non-blocking audio pipeline
/// Result of a language switch attempt, including availability status and fallback details.
class LanguageSwitchResult {
  const LanguageSwitchResult({
    required this.targetLanguage,
    required this.activeLanguage,
    required this.isSupported,
    this.fallbackReason,
  });

  final AppLanguage targetLanguage;
  final AppLanguage activeLanguage;
  final bool isSupported;
  final String? fallbackReason;
}

class SpeechService {
  SpeechService({this.minGap = const Duration(milliseconds: 2400)});

  final Duration minGap;
  final FlutterTts _tts = FlutterTts();

  bool _ready = false;
  bool _isSpeaking = false;
  String _lastPhrase = '';
  DateTime _lastSpokeAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSpokeFinishedAt = DateTime.fromMillisecondsSinceEpoch(0);
  AppLanguage _currentLanguage = AppLanguage.english;

  bool get isReady => _ready;
  bool get isSpeaking => _isSpeaking;
  AppLanguage get currentLanguage => _currentLanguage;

  Future<LanguageSwitchResult?> initialize({AppLanguage? language}) async {
    try {
      final preferred = language ?? SettingsService.instance.preferredLanguage;
      await _tts.setSpeechRate(SettingsService.instance.speechRate);
      await _tts.setPitch(1.0);
      try {
        await _tts.awaitSpeakCompletion(true);
      } catch (_) {}

      _tts.setStartHandler(() {
        _isSpeaking = true;
      });
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        _lastSpokeFinishedAt = DateTime.now();
      });
      _tts.setCancelHandler(() {
        _isSpeaking = false;
        _lastSpokeFinishedAt = DateTime.now();
      });
      _tts.setErrorHandler((_) {
        _isSpeaking = false;
        _lastSpokeFinishedAt = DateTime.now();
      });

      _ready = true;
      return await setLanguage(preferred);
    } catch (_) {
      _ready = false;
      return null;
    }
  }

  /// Queries installed language tags from the platform TextToSpeech engine.
  Future<List<String>> getInstalledLanguages() async {
    if (!_ready) return const ['en-US'];
    try {
      final langs = await _tts.getLanguages;
      if (langs is List) {
        return langs.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const ['en-US'];
  }

  bool _isTtsAvailable(dynamic res) {
    if (res == true) return true;
    if (res is num && res >= 0) return true;
    return false;
  }

  /// Checks if [language] is supported/installed in Android TextToSpeech.
  Future<bool> isLanguageSupported(AppLanguage language) async {
    if (!_ready) return language == AppLanguage.english;
    try {
      try {
        final installedRes = await _tts.isLanguageInstalled(language.locale);
        if (_isTtsAvailable(installedRes)) return true;
        final installedCode = await _tts.isLanguageInstalled(language.code);
        if (_isTtsAvailable(installedCode)) return true;
      } catch (_) {}

      final res = await _tts.isLanguageAvailable(language.locale);
      if (_isTtsAvailable(res)) return true;

      // Try base language code (e.g., 'kn' instead of 'kn-IN', 'hi' instead of 'hi-IN')
      final resCode = await _tts.isLanguageAvailable(language.code);
      if (_isTtsAvailable(resCode)) return true;

      // Also check against getLanguages list if available
      final installed = await getInstalledLanguages();
      final hasLocale = installed.any((l) {
        final lower = l.toLowerCase();
        return lower == language.locale.toLowerCase() ||
            lower == language.code.toLowerCase() ||
            lower.startsWith('${language.code.toLowerCase()}-') ||
            lower.startsWith('${language.code.toLowerCase()}_');
      });
      if (hasLocale) return true;

      return false;
    } catch (_) {
      return language == AppLanguage.english;
    }
  }

  /// Changes the TTS engine language and reconfigures locale.
  /// If the requested voice is not installed on the device,
  /// falls back to English and returns a [LanguageSwitchResult].
  Future<LanguageSwitchResult> setLanguage(AppLanguage language) async {
    if (!_ready) {
      _currentLanguage = language;
      return LanguageSwitchResult(
        targetLanguage: language,
        activeLanguage: language,
        isSupported: true,
      );
    }
    try {
      await stop();

      final available = await isLanguageSupported(language);
      if (available) {
        dynamic setRes = await _tts.setLanguage(language.locale);
        if (_isTtsAvailable(setRes)) {
          _currentLanguage = language;
          return LanguageSwitchResult(
            targetLanguage: language,
            activeLanguage: language,
            isSupported: true,
          );
        }
        setRes = await _tts.setLanguage(language.code);
        if (_isTtsAvailable(setRes)) {
          _currentLanguage = language;
          return LanguageSwitchResult(
            targetLanguage: language,
            activeLanguage: language,
            isSupported: true,
          );
        }
      }

      // Voice data not installed for requested language — fallback to English
      await _tts.setLanguage(AppLanguage.english.locale);
      _currentLanguage = AppLanguage.english;
      return LanguageSwitchResult(
        targetLanguage: language,
        activeLanguage: AppLanguage.english,
        isSupported: false,
        fallbackReason:
            '${language.englishName} voice is not installed on this device.',
      );
    } catch (_) {
      _currentLanguage = AppLanguage.english;
      return LanguageSwitchResult(
        targetLanguage: language,
        activeLanguage: AppLanguage.english,
        isSupported: false,
        fallbackReason: 'Failed to configure ${language.englishName} voice.',
      );
    }
  }

  Future<void> updateSettings() async {
    if (!_ready) return;
    try {
      await _tts.setSpeechRate(SettingsService.instance.speechRate);
      await setLanguage(SettingsService.instance.preferredLanguage);
    } catch (_) {}
  }

  /// Speaks [phrase] according to speech priority and cooldown guidelines.
  ///
  /// Set [urgent] to true for milestones such as "Stop. Bottle found.",
  /// "Target detected.", or error announcements.
  Future<void> speak(String phrase, {bool urgent = false}) async {
    if (!SettingsService.instance.voiceGuidance) return;
    final trimmed = phrase.trim();
    if (!_ready || trimmed.isEmpty) return;

    final now = DateTime.now();
    if (!urgent) {
      // Do not overlap: if currently speaking, ignore non-urgent utterance
      if (_isSpeaking) return;

      // Avoid repetitive chatter:
      if (trimmed == _lastPhrase && now.difference(_lastSpokeAt) < minGap) {
        return;
      }

      // Ensure natural pause (at least 600ms) after the previous speech finished
      if (now.difference(_lastSpokeFinishedAt) < const Duration(milliseconds: 600)) {
        return;
      }

      // Require at least 1.4s between start of different guidance phrases:
      if (trimmed != _lastPhrase &&
          now.difference(_lastSpokeAt) < const Duration(milliseconds: 1400)) {
        return;
      }
    } else {
      // Urgent milestones stop any previous utterance and speak immediately
      await _tts.stop();
      _isSpeaking = false;
    }

    _lastPhrase = trimmed;
    _lastSpokeAt = now;
    _isSpeaking = true;
    try {
      await _tts.speak(trimmed);
    } catch (_) {
      // Voice engine error must never crash guidance pipeline
      _isSpeaking = false;
    }
  }

  /// Speaks [phrase] immediately without minGap throttling, optionally switching to [language].
  Future<void> speakImmediately(String phrase, {AppLanguage? language}) async {
    final trimmed = phrase.trim();
    if (!_ready || trimmed.isEmpty) return;
    try {
      await _tts.stop();
      _isSpeaking = false;
      if (language != null) {
        await setLanguage(language);
      }
      _lastPhrase = trimmed;
      _lastSpokeAt = DateTime.now();
      _isSpeaking = true;
      await _tts.speak(trimmed);
    } catch (_) {
      _isSpeaking = false;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
    _lastPhrase = '';
    _lastSpokeFinishedAt = DateTime.now();
  }

  Future<void> dispose() async {
    await stop();
  }
}
