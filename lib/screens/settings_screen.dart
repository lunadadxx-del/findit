import 'package:flutter/material.dart';

import '../models/app_language.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';
import 'language_selection_screen.dart';
import 'lost_phone_screen.dart';

/// Screen 5 — Modern, Accessible Settings & Preferences
///
/// Features:
/// - Cohesive card-based settings layout.
/// - Profile & Multilingual Voice selector with instant audio preview.
/// - Tactile toggles for Voice Guidance and Haptic Proximity Feedback.
/// - On-Device AI tuning (sensitivity, Hackathon telemetry HUD).
/// - Privacy controls with local data reset.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService.instance;
  final SpeechService _speech = SpeechService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _nameController.text = _settings.userName;
    _apiKeyController.text = _settings.geminiApiKey;
  }

  Future<void> _initSpeech() async {
    final result = await _speech.initialize();
    if (result != null && !result.isSupported && mounted) {
      _settings.setPreferredLanguage(AppLanguage.english);
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _nameController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  void _testSpeech() {
    final lang = _speech.currentLanguage;
    final testMsg = switch (lang) {
      AppLanguage.english => 'FindIt voice guidance is active at this speed.',
      AppLanguage.hindi => 'FindIt आवाज़ मार्गदर्शन इस गति पर सक्रिय है।',
      AppLanguage.kannada => 'FindIt ಧ್ವನಿ ಮಾರ್ಗದರ್ಶನ ಈ ವೇಗದಲ್ಲಿ ಸಕ್ರಿಯವಾಗಿದೆ.',
      AppLanguage.telugu =>
        'FindIt వాయిస్ మార్గదర్శకత్వం ఈ వేగంతో పనిచేస్తుంది.',
      AppLanguage.tamil =>
        'FindIt குரல் வழிகாட்டல் இந்த வேகத்தில் செயல்படுகிறது.',
    };
    _speech.speak(testMsg, urgent: true);
  }

  Future<void> _onLanguageSelected(AppLanguage lang) async {
    final result = await _speech.setLanguage(lang);
    if (!result.isSupported) {
      _settings.setPreferredLanguage(AppLanguage.english);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${lang.englishName} voice is not installed on this device. Reverted to English.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      await _speech.speak(
        '${lang.englishName} voice is not installed on this device. Using English.',
        urgent: true,
      );
    } else {
      _settings.setPreferredLanguage(lang);
      final ack = LocalizationService.instance.languageChangedAck(lang);
      await _speech.speak(ack, urgent: true);
    }
  }

  void _confirmClearData() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset All Local Data?'),
        content: const Text(
          'This will clear your saved name, language preference, and reset FindIt to the first-launch setup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _settings.clearAllData();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) =>
                        const LanguageSelectionScreen(isFirstLaunch: true),
                  ),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('RESET & RESTART'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              tooltip: 'Back',
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Settings & Accessibility'),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // Section: User Profile
                _buildSectionHeader('USER PROFILE'),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Personalize Assistant Greeting',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 17,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter your name (e.g. Pavan)',
                          prefixIcon: const Icon(
                            Icons.badge_outlined,
                            color: AppTheme.primary,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(
                              Icons.check_circle_outline,
                              color: AppTheme.success,
                            ),
                            onPressed: () {
                              _settings.setUserName(_nameController.text);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Name saved!')),
                              );
                            },
                          ),
                        ),
                        onSubmitted: (val) => _settings.setUserName(val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section: Language Selection
                _buildSectionHeader('VOICE & GUIDANCE LANGUAGE'),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select preferred voice language:',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: AppLanguage.values.map((lang) {
                          final isSelected =
                              lang == _settings.preferredLanguage;
                          return ChoiceChip(
                            label: Text(
                              '${lang.nativeName} (${lang.englishName})',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.black
                                    : AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: AppTheme.primary,
                            backgroundColor: AppTheme.surfaceElevated,
                            side: BorderSide(
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.borderSubtle,
                            ),
                            onSelected: (val) {
                              if (val) _onLanguageSelected(lang);
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      // Accessible button to open the voice-first selection screen
                      Semantics(
                        button: true,
                        label: 'Open voice-first language selection screen with volume button controls',
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LanguageSelectionScreen(
                                  isFirstLaunch: false,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.hearing, color: AppTheme.primary),
                          label: const Text(
                            'VOICE & VOLUME BUTTON SELECTOR',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.primary, width: 1.5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section: Voice Guidance
                _buildSectionHeader('VOICE GUIDANCE CONTROLS'),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppTheme.primary,
                        title: const Text(
                          'Directional Voice Guidance',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text(
                          'Speaks directions ("Move left", "Getting closer", "Stop")',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        value: _settings.voiceGuidance,
                        onChanged: (val) {
                          _settings.setVoiceGuidance(val);
                          if (val) _speech.speak('Voice guidance enabled.');
                        },
                      ),
                      const Divider(color: AppTheme.borderSubtle, height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Speech Rate',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${(_settings.speechRate * 2.0).toStringAsFixed(1)}x',
                            style: const TextStyle(
                              color: AppTheme.primaryLight,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _settings.speechRate.clamp(0.35, 0.75),
                        min: 0.35,
                        max: 0.75,
                        divisions: 8,
                        activeColor: AppTheme.primary,
                        inactiveColor: AppTheme.surfaceHighlight,
                        onChanged: (val) {
                          _settings.setSpeechRate(val);
                          _speech.updateSettings();
                        },
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _testSpeech,
                          icon: const Icon(
                            Icons.volume_up_rounded,
                            color: AppTheme.primary,
                          ),
                          label: const Text(
                            'TEST VOICE SPEED',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section: Haptics
                _buildSectionHeader('HAPTIC PROXIMITY FEEDBACK'),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: AppTheme.primary,
                    title: const Text(
                      'Vibration Pulses',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      'Haptic pulse rate increases as you close in on the object',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                    ),
                    value: _settings.hapticFeedback,
                    onChanged: (val) => _settings.setHapticFeedback(val),
                  ),
                ),
                 // Section: Lost Phone Mode
                _buildSectionHeader('LOST PHONE & SAFETY'),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.phone_android_rounded,
                            color: AppTheme.primary,
                            size: 26,
                          ),
                        ),
                        title: const Text(
                          'Lost Phone Mode',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text(
                          'Compliant foreground service listening for "Hey Iris" with auto-shutoff to protect battery.',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: AppTheme.textMuted,
                          size: 16,
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LostPhoneScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section: AI Tuning
                _buildSectionHeader('ON-DEVICE AI TUNING'),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Confidence Threshold',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${(_settings.confidenceThreshold * 100).toInt()}%',
                            style: const TextStyle(
                              color: AppTheme.primaryLight,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _settings.confidenceThreshold,
                        min: 0.25,
                        max: 0.70,
                        divisions: 9,
                        activeColor: AppTheme.primary,
                        inactiveColor: AppTheme.surfaceHighlight,
                        onChanged: (val) =>
                            _settings.setConfidenceThreshold(val),
                      ),
                      const Divider(color: AppTheme.borderSubtle, height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppTheme.primary,
                        title: const Text(
                          'Show Hackathon AI HUD',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text(
                          'Displays inference latency (ms), confidence %, and camera metrics',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                        value: _settings.showDebugStats,
                        onChanged: (val) => _settings.setShowDebugStats(val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section: Cloud AI (Optional)
                _buildSectionHeader('OPTIONAL CLOUD AI (GEMINI)'),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Core object finding runs 100% on-device offline. Cloud AI can optionally parse complex natural language phrasing.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: AppTheme.primary,
                        title: const Text(
                          'Enable Cloud Assistant Features',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        value: _settings.cloudAiEnabled,
                        onChanged: (val) => _settings.setCloudAiEnabled(val),
                      ),
                      if (_settings.cloudAiEnabled) ...[
                        const SizedBox(height: 10),
                        TextField(
                          controller: _apiKeyController,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                          ),
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'Enter Gemini API key',
                            prefixIcon: const Icon(
                              Icons.vpn_key_outlined,
                              color: AppTheme.primary,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(
                                Icons.save_outlined,
                                color: AppTheme.success,
                              ),
                              onPressed: () {
                                _settings.setGeminiApiKey(
                                  _apiKeyController.text,
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('API Key saved!'),
                                  ),
                                );
                              },
                            ),
                          ),
                          onSubmitted: (val) => _settings.setGeminiApiKey(val),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section: Safety Boundary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(
                        Icons.shield_outlined,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'FindIt is an assistive finder for indoor everyday objects. It is not a medical device or white cane replacement.',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Section: Reset Data
                Semantics(
                  button: true,
                  label: 'Delete all local data and reset app',
                  child: OutlinedButton.icon(
                    onPressed: _confirmClearData,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: AppTheme.error,
                    ),
                    label: const Text('RESET ALL LOCAL DATA'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0, left: 4.0),
      child: Text(
        title,
        style: const TextStyle(
          color: AppTheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}
