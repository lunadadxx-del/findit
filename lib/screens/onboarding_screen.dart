import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/app_language.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

/// Screen 0 — Modern, Accessible Welcome & Onboarding Experience
///
/// Features:
/// - Clear FindIt branding & purpose explanation.
/// - Tactile, accessible language selection with immediate audio preview.
/// - Optional name input via voice speech-to-text or accessible text field.
/// - High-contrast, large touch affordances (TalkBack ready).
/// - Prominent "Get Started" action.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final SpeechService _speech = SpeechService();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final TextEditingController _nameController = TextEditingController();
  final SettingsService _settings = SettingsService.instance;
  final LocalizationService _l10n = LocalizationService.instance;

  bool _isListening = false;
  bool _speechAvailable = false;
  AppLanguage _selectedLanguage = AppLanguage.english;

  @override
  void initState() {
    super.initState();
    _selectedLanguage = _settings.preferredLanguage;
    _nameController.text = _settings.userName;
    _initVoice();
  }

  Future<void> _initVoice() async {
    await _speech.initialize(language: _selectedLanguage);
    try {
      final mic = await Permission.microphone.status;
      if (!mic.isGranted) {
        await Permission.microphone.request();
      }
      _speechAvailable = await _speechToText.initialize();
    } catch (_) {
      _speechAvailable = false;
    }

    // Audio greeting after screen mounts
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _speech.speak(
          "Welcome to FindIt. Select your language and tap Get Started.",
          urgent: true,
        );
      }
    });
  }

  @override
  void dispose() {
    _speech.stop();
    _speechToText.stop();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectLanguage(AppLanguage language) async {
    final result = await _speech.setLanguage(language);
    if (!result.isSupported) {
      setState(() => _selectedLanguage = AppLanguage.english);
      _settings.setPreferredLanguage(AppLanguage.english);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${language.englishName} voice is not installed on this device. Defaulting to English.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      await _speech.speak(
        '${language.englishName} voice is not installed on this device. Using English.',
        urgent: true,
      );
      return;
    }

    setState(() => _selectedLanguage = language);
    _settings.setPreferredLanguage(language);

    final ack = _l10n.languageChangedAck(language);
    await _speech.speak(ack, urgent: true);
  }

  Future<void> _startListeningForName() async {
    if (_isListening) {
      await _speechToText.stop();
      setState(() => _isListening = false);
      return;
    }

    if (!_speechAvailable) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) return;
      _speechAvailable = await _speechToText.initialize();
    }

    setState(() => _isListening = true);
    try {
      await _speechToText.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty && mounted) {
            setState(() {
              _nameController.text = words;
            });
          }
          if (result.finalResult && words.isNotEmpty) {
            _saveName(words);
          }
        },
        // ignore: deprecated_member_use
        localeId: _selectedLanguage.locale,
      );
    } catch (_) {
      setState(() => _isListening = false);
    }
  }

  void _saveName(String name) {
    setState(() => _isListening = false);
    final clean = name.trim();
    if (clean.isNotEmpty) {
      _settings.setUserName(clean);
      final ack = _l10n.niceToMeetYou(clean, _selectedLanguage);
      _speech.speak(ack, urgent: true);
    }
  }

  void _getStarted() {
    final cleanName = _nameController.text.trim();
    if (cleanName.isNotEmpty) {
      _settings.setUserName(cleanName);
    }
    _settings.setFirstLaunchCompleted();
    _speech.stop();
    _speechToText.stop();

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // Hero Assistive Badge & Branding
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceHighlight,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '100% ON-DEVICE AI • ASSISTIVE SEARCH',
                        style: TextStyle(
                          color: AppTheme.primaryLight,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Brand Icon & Title
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primary, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.25),
                        blurRadius: 28,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.explore_rounded,
                    size: 48,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'FindIt',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),

              // Purpose Explanation
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Your smart vision assistant for everyday objects. Closed-loop audio guidance and haptic pulses bring you right to what you lost.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Accessibility Highlights Chips
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _FeaturePill(icon: Icons.hearing, label: 'Voice Guidance'),
                  _FeaturePill(icon: Icons.vibration, label: 'Haptic Radar'),
                  _FeaturePill(
                    icon: Icons.wifi_off,
                    label: 'No Internet Needed',
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Language Selection Section
              Semantics(
                header: true,
                child: const Text(
                  'CHOOSE YOUR LANGUAGE / भाषा चुनें',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Language Option Cards
              Column(
                children: AppLanguage.values.map((lang) {
                  final isSelected = lang == _selectedLanguage;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: Semantics(
                      button: true,
                      selected: isSelected,
                      label: '${lang.englishName}, ${lang.nativeName}',
                      child: InkWell(
                        onTap: () => _selectLanguage(lang),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.surfaceElevated
                                : AppTheme.surface,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMd,
                            ),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.borderSubtle,
                              width: isSelected ? 2.0 : 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primary
                                        : AppTheme.textMuted,
                                    width: 2,
                                  ),
                                  color: isSelected
                                      ? AppTheme.primary
                                      : Colors.transparent,
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Colors.black,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      lang.nativeName,
                                      style: TextStyle(
                                        color: isSelected
                                            ? AppTheme.primaryLight
                                            : AppTheme.textPrimary,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      lang.englishName,
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.volume_up_rounded,
                                  color: AppTheme.primary,
                                  size: 22,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Name Capture Card (Optional)
              Semantics(
                header: true,
                child: const Text(
                  'WHAT SHOULD WE CALL YOU? (OPTIONAL)',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter your name',
                        prefixIcon: const Icon(
                          Icons.person_outline_rounded,
                          color: AppTheme.primary,
                        ),
                        suffixIcon: _nameController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: AppTheme.textMuted,
                                ),
                                onPressed: () {
                                  setState(() => _nameController.clear());
                                  _settings.setUserName('');
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) => _settings.setUserName(val.trim()),
                      onSubmitted: _saveName,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Mic button for accessible voice name input
                  Semantics(
                    button: true,
                    label: _isListening
                        ? 'Stop listening'
                        : 'Speak your name into microphone',
                    child: GestureDetector(
                      onTap: _startListeningForName,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: _isListening
                              ? AppTheme.listening
                              : AppTheme.surfaceElevated,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isListening
                                ? AppTheme.error
                                : AppTheme.primary,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: _isListening ? Colors.white : AppTheme.primary,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),

              // Prominent Primary Action: Get Started
              Semantics(
                button: true,
                label: 'Get started and open FindIt main screen',
                child: ElevatedButton(
                  onPressed: _getStarted,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    elevation: 4,
                    shadowColor: AppTheme.primary.withValues(alpha: 0.4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text(
                        'GET STARTED',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(width: 10),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 24,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
