import 'package:flutter/material.dart';

import '../models/app_language.dart';
import '../models/target_objects.dart';
import '../services/haptic_service.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';
import 'object_selection_screen.dart';

/// Screen 4 — Modern, Celebratory Object Found Screen
///
/// Features:
/// - Prominent emerald confirmation badge with glowing shadow.
/// - Unmistakable "[Object] Found!" typography for low-vision glanceability.
/// - Clear, high-contrast action buttons: "Find Another Object" and "Done".
/// - Triple-pulse celebration haptics & urgent voice confirmation.
class FoundScreen extends StatefulWidget {
  const FoundScreen({super.key, required this.targetFriendly});

  final String targetFriendly;

  @override
  State<FoundScreen> createState() => _FoundScreenState();
}

class _FoundScreenState extends State<FoundScreen> {
  final SpeechService _speech = SpeechService();
  final HapticService _haptics = HapticService();
  final SettingsService _settings = SettingsService.instance;

  AppLanguage get _lang => _settings.preferredLanguage;
  String get _localizedName =>
      LocalizationService.instance.objectName(widget.targetFriendly, _lang);

  @override
  void initState() {
    super.initState();
    _celebrate();
  }

  Future<void> _celebrate() async {
    await _haptics.initialize();
    final langResult = await _speech.initialize(language: _lang);
    if (langResult != null && !langResult.isSupported && _lang != AppLanguage.english) {
      _settings.setPreferredLanguage(AppLanguage.english);
    }

    await _haptics.foundCelebration();
    final activeLang = _speech.currentLanguage;
    final message = LocalizationService.instance.stopObjectFound(
      widget.targetFriendly,
      activeLang,
    );
    await _speech.speak(message);
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  void _findAnother() {
    _speech.stop();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ObjectSelectionScreen()),
    );
  }

  void _done() {
    _speech.stop();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final icon = TargetObjects.iconFor(widget.targetFriendly);
    final capitalized =
        _localizedName[0].toUpperCase() + _localizedName.substring(1);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),

              // Celebratory Icon Badge with Radiant Emerald Halo
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.success,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.success.withValues(alpha: 0.5),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: Icon(icon, size: 76, color: Colors.black),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.success,
                            width: 2.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: AppTheme.success,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Large Header
              Semantics(
                header: true,
                child: const Text(
                  'OBJECT LOCATED!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.success,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                '$capitalized is in front of you',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),

              Semantics(
                liveRegion: true,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Text(
                    LocalizationService.instance.stopObjectFound(
                      widget.targetFriendly,
                      _lang,
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Primary Action: Find Another Object
              Semantics(
                button: true,
                label: 'Find another object',
                child: ElevatedButton.icon(
                  onPressed: _findAnother,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 26,
                    color: Colors.black,
                  ),
                  label: const Text('FIND ANOTHER OBJECT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Secondary Action: Return Home
              Semantics(
                button: true,
                label: 'Done and return to home screen',
                child: OutlinedButton.icon(
                  onPressed: _done,
                  icon: const Icon(Icons.home_outlined, size: 24),
                  label: const Text('RETURN TO HOME'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
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
