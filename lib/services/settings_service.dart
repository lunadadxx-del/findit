import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_language.dart';

/// App-wide settings for accessibility, voice, language, profile, and AI.
///
/// Persisted locally via SharedPreferences without any external accounts,
/// email, or tracking per PRD Section 4 & 34.
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const String _keyUserName = 'findit_user_name';
  static const String _keyLanguage = 'findit_preferred_language';
  static const String _keyVoiceGuidance = 'findit_voice_guidance';
  static const String _keyHapticFeedback = 'findit_haptic_feedback';
  static const String _keySpeechRate = 'findit_speech_rate';
  static const String _keyConfidenceThreshold = 'findit_confidence_threshold';
  static const String _keyHighContrast = 'findit_high_contrast';
  static const String _keyShowDebugStats = 'findit_show_debug_stats';
  static const String _keyFirstLaunch = 'findit_first_launch_done';
  static const String _keyCloudAiEnabled = 'findit_cloud_ai_enabled';
  static const String _keyGeminiApiKey = 'findit_gemini_api_key';

  SharedPreferences? _prefs;

  String _userName = '';
  AppLanguage _preferredLanguage = AppLanguage.english;
  bool _voiceGuidance = true;
  bool _hapticFeedback = true;
  double _speechRate = 0.50;
  double _confidenceThreshold = 0.40;
  bool _highContrast = true;
  bool _showDebugStats = false;
  bool _isFirstLaunch = true;
  bool _cloudAiEnabled = false;
  String _geminiApiKey = '';

  String get userName => _userName;
  AppLanguage get preferredLanguage => _preferredLanguage;
  bool get voiceGuidance => _voiceGuidance;
  bool get hapticFeedback => _hapticFeedback;
  double get speechRate => _speechRate;
  double get confidenceThreshold => _confidenceThreshold;
  bool get highContrast => _highContrast;
  bool get showDebugStats => _showDebugStats;
  bool get isFirstLaunch => _isFirstLaunch;
  bool get cloudAiEnabled => _cloudAiEnabled;
  String get geminiApiKey => _geminiApiKey;

  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _userName = _prefs?.getString(_keyUserName) ?? '';
      final langCode = _prefs?.getString(_keyLanguage);
      _preferredLanguage = AppLanguage.fromCode(langCode);
      _voiceGuidance = _prefs?.getBool(_keyVoiceGuidance) ?? true;
      _hapticFeedback = _prefs?.getBool(_keyHapticFeedback) ?? true;
      _speechRate = _prefs?.getDouble(_keySpeechRate) ?? 0.50;
      _confidenceThreshold = _prefs?.getDouble(_keyConfidenceThreshold) ?? 0.40;
      _highContrast = _prefs?.getBool(_keyHighContrast) ?? true;
      _showDebugStats = _prefs?.getBool(_keyShowDebugStats) ?? false;
      // If key is present and true, first launch is false
      final firstLaunchDone = _prefs?.getBool(_keyFirstLaunch) ?? false;
      _isFirstLaunch = !firstLaunchDone;
      _cloudAiEnabled = _prefs?.getBool(_keyCloudAiEnabled) ?? false;
      _geminiApiKey = _prefs?.getString(_keyGeminiApiKey) ?? '';
      notifyListeners();
    } catch (_) {
      // Graceful fallback to default in-memory values
    }
  }

  void setUserName(String name) {
    _userName = name.trim();
    _prefs?.setString(_keyUserName, _userName);
    notifyListeners();
  }

  void setPreferredLanguage(AppLanguage language) {
    _preferredLanguage = language;
    _prefs?.setString(_keyLanguage, language.code);
    notifyListeners();
  }

  void setVoiceGuidance(bool value) {
    _voiceGuidance = value;
    _prefs?.setBool(_keyVoiceGuidance, value);
    notifyListeners();
  }

  void setHapticFeedback(bool value) {
    _hapticFeedback = value;
    _prefs?.setBool(_keyHapticFeedback, value);
    notifyListeners();
  }

  void setSpeechRate(double value) {
    _speechRate = value;
    _prefs?.setDouble(_keySpeechRate, value);
    notifyListeners();
  }

  void setConfidenceThreshold(double value) {
    _confidenceThreshold = value;
    _prefs?.setDouble(_keyConfidenceThreshold, value);
    notifyListeners();
  }

  void setHighContrast(bool value) {
    _highContrast = value;
    _prefs?.setBool(_keyHighContrast, value);
    notifyListeners();
  }

  void setShowDebugStats(bool value) {
    _showDebugStats = value;
    _prefs?.setBool(_keyShowDebugStats, value);
    notifyListeners();
  }

  void setFirstLaunchCompleted() {
    _isFirstLaunch = false;
    _prefs?.setBool(_keyFirstLaunch, true);
    notifyListeners();
  }

  void setCloudAiEnabled(bool value) {
    _cloudAiEnabled = value;
    _prefs?.setBool(_keyCloudAiEnabled, value);
    notifyListeners();
  }

  void setGeminiApiKey(String key) {
    _geminiApiKey = key.trim();
    _prefs?.setString(_keyGeminiApiKey, _geminiApiKey);
    notifyListeners();
  }

  Future<void> clearAllData() async {
    _userName = '';
    _preferredLanguage = AppLanguage.english;
    _voiceGuidance = true;
    _hapticFeedback = true;
    _speechRate = 0.50;
    _confidenceThreshold = 0.40;
    _isFirstLaunch = true;
    _cloudAiEnabled = false;
    _geminiApiKey = '';
    await _prefs?.clear();
    notifyListeners();
  }
}
