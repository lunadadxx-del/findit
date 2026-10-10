import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_language.dart';
import '../services/haptic_service.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../services/volume_key_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

/// Screen — Accessible, Voice-First Language Selection for Blind Users.
///
/// Complies with all PRD accessibility and multimodal guidance requirements:
/// 1. Announces options sequentially in English, Hindi, and Kannada on mount.
/// 2. Hardware Volume Up/Down cycles through options with spoken and haptic feedback.
/// 3. Confirms selection via simultaneous volume buttons, long-press volume button,
///    or screen double-tap.
/// 4. Persists language choice and updates app-wide speech & guidance.
/// 5. Offers full spoken instructions, tactile audio feedback, and replay capability.
/// 6. Enforces native volume interception ONLY on this screen; standard volume behavior
///    remains completely unaltered across the rest of the application.
class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({
    super.key,
    this.isFirstLaunch = true,
  });

  final bool isFirstLaunch;

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen>
    with WidgetsBindingObserver {
  final SettingsService _settings = SettingsService.instance;
  final SpeechService _speech = SpeechService();
  final HapticService _haptics = HapticService();
  final VolumeKeyService _volumeKeys = VolumeKeyService.instance;

  // The 3 primary voice languages specified by requirement 1
  static const List<AppLanguage> _languages = [
    AppLanguage.english,
    AppLanguage.hindi,
    AppLanguage.kannada,
  ];

  int _selectedIndex = 0;
  bool _isAnnouncing = false;
  int _announcementId = 0;
  StreamSubscription<VolumeKeyEvent>? _volumeSub;
  final FocusNode _focusNode = FocusNode();
  final Map<Timer, Completer<void>> _activeDelays = {};

  Future<void> _cancellableDelay(Duration duration) {
    final completer = Completer<void>();
    late final Timer timer;
    timer = Timer(duration, () {
      _activeDelays.remove(timer);
      if (!completer.isCompleted) completer.complete();
    });
    _activeDelays[timer] = completer;
    return completer.future;
  }

  void _clearPendingTimers() {
    for (final entry in _activeDelays.entries) {
      entry.key.cancel();
      if (!entry.value.isCompleted) {
        entry.value.complete();
      }
    }
    _activeDelays.clear();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initial language index based on saved preference if present
    final currentPref = _settings.preferredLanguage;
    final matchIdx = _languages.indexOf(currentPref);
    _selectedIndex = matchIdx >= 0 ? matchIdx : 0;

    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _haptics.initialize();
    await _speech.initialize(language: _languages[_selectedIndex]);

    // Enable hardware volume button interception exclusively for this screen
    await _volumeKeys.enableInterception();

    // Listen to hardware volume button events
    _volumeSub = _volumeKeys.events.listen(_handleVolumeKeyEvent);

    // Play spoken walkthrough after view mounts
    if (mounted) {
      _startWalkthroughAnnouncement();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _volumeKeys.enableInterception();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _volumeKeys.disableInterception();
      _stopAnnouncement();
      _speech.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAnnouncement();
    _clearPendingTimers();
    _volumeSub?.cancel();
    _volumeKeys.disableInterception();
    _speech.stop();
    _focusNode.dispose();
    super.dispose();
  }

  void _stopAnnouncement() {
    _announcementId++;
    _isAnnouncing = false;
    _clearPendingTimers();
  }

  /// Announces the full instructions and each language option in its native tongue.
  Future<void> _startWalkthroughAnnouncement() async {
    _stopAnnouncement();
    final currentId = _announcementId;
    setState(() => _isAnnouncing = true);

    try {
      await _speech.stop();

      // Step 1: Clear spoken instructions in English
      await _speech.setLanguage(AppLanguage.english);
      if (_announcementId != currentId || !mounted) return;
      await _speech.speakImmediately(
        'Welcome to FindIt. Select your language. Use Volume Up or Volume Down to choose. Press both volume buttons together, hold a volume button, or double-tap the screen to confirm. Here are your options:',
        language: AppLanguage.english,
      );

      // Brief natural pause
      await _cancellableDelay(const Duration(milliseconds: 400));
      if (_announcementId != currentId || !mounted) return;

      // Option 1: English (spoken in English)
      await _speech.speakImmediately('Option 1: English.', language: AppLanguage.english);
      await _cancellableDelay(const Duration(milliseconds: 350));
      if (_announcementId != currentId || !mounted) return;

      // Option 2: Hindi (spoken in Hindi)
      await _speech.speakImmediately('विकल्प दो: हिंदी।', language: AppLanguage.hindi);
      await _cancellableDelay(const Duration(milliseconds: 350));
      if (_announcementId != currentId || !mounted) return;

      // Option 3: Kannada (spoken in Kannada)
      await _speech.speakImmediately('ಆಯ್ಕೆ ಮೂರು: ಕನ್ನಡ.', language: AppLanguage.kannada);
      await _cancellableDelay(const Duration(milliseconds: 350));
      if (_announcementId != currentId || !mounted) return;

      // Concluding instruction indicating current highlighted option
      final activeLang = _languages[_selectedIndex];
      await _speech.setLanguage(activeLang);
      final currentPhrase = switch (activeLang) {
        AppLanguage.english => 'Currently selected: English. Press both volume buttons, hold either button, or double-tap to confirm.',
        AppLanguage.hindi => 'वर्तमान चयन: हिंदी। पुष्टि करने के लिए दोनों वॉल्यूम बटन एक साथ दबाएं, किसी एक को दबाए रखें, या स्क्रीन पर दो बार टैप करें।',
        AppLanguage.kannada => 'ಪ್ರಸ್ತುತ ಆಯ್ಕೆ: ಕನ್ನಡ. ಖಚಿತಪಡಿಸಲು ಎರಡೂ ವಾಲ್ಯೂಮ್ ಬಟನ್‌ಗಳನ್ನು ಒಟ್ಟಿಗೆ ಒತ್ತಿ, ಒಂದನ್ನು ಹಿಡಿದುಕೊಳ್ಳಿ, ಅಥವಾ ಪರದೆಯನ್ನು ಎರಡು ಬಾರಿ ಟ್ಯಾಪ್ ಮಾಡಿ.',
        _ => 'Option selected.',
      };
      await _speech.speakImmediately(currentPhrase, language: activeLang);
    } catch (_) {
      // Audio pipeline errors must not crash navigation
    } finally {
      if (mounted && _announcementId == currentId) {
        setState(() => _isAnnouncing = false);
      }
    }
  }

  void _handleVolumeKeyEvent(VolumeKeyEvent event) {
    if (!mounted) return;

    // Any user key interaction immediately cancels the automatic walkthrough
    _stopAnnouncement();

    switch (event.type) {
      case VolumeKeyEventType.up:
        _cycleSelection(1);
        break;
      case VolumeKeyEventType.down:
        _cycleSelection(-1);
        break;
      case VolumeKeyEventType.confirm:
        _confirmSelection(detail: event.detail);
        break;
    }
  }

  /// Cycles through language options and speaks the newly selected language in its tongue.
  Future<void> _cycleSelection(int delta) async {
    _stopAnnouncement();

    setState(() {
      _selectedIndex = (_selectedIndex + delta) % _languages.length;
      if (_selectedIndex < 0) {
        _selectedIndex = _languages.length - 1;
      }
    });

    final lang = _languages[_selectedIndex];

    // Tactile tick
    await _haptics.selectionTick();

    // Spoken feedback in the selected language
    final phrase = switch (lang) {
      AppLanguage.english => 'Option 1: English.',
      AppLanguage.hindi => 'विकल्प दो: हिंदी।',
      AppLanguage.kannada => 'ಆಯ್ಕೆ ಮೂರು: ಕನ್ನಡ.',
      _ => 'Option ${_selectedIndex + 1}: ${lang.englishName}.',
    };

    await _speech.setLanguage(lang);
    await _speech.speakImmediately(phrase, language: lang);
  }

  /// Confirms the active language selection and transitions into FindIt.
  Future<void> _confirmSelection({String detail = 'tap'}) async {
    _stopAnnouncement();

    final chosen = _languages[_selectedIndex];

    // Distinct tactile confirmation pulse
    await _haptics.confirmed();

    // Save language to user settings
    _settings.setPreferredLanguage(chosen);
    if (widget.isFirstLaunch) {
      _settings.setFirstLaunchCompleted();
    }

    // Audio feedback in selected language
    final confirmation = switch (chosen) {
      AppLanguage.english => 'English confirmed. Welcome to FindIt.',
      AppLanguage.hindi => 'हिंदी चुनी गई। FindIt में आपका स्वागत है।',
      AppLanguage.kannada => 'ಕನ್ನಡ ಆಯ್ಕೆಮಾಡಲಾಗಿದೆ. FindIt ಗೆ ಸುಸ್ವಾಗತ.',
      _ => '${chosen.englishName} confirmed.',
    };

    // Speak confirmation
    await _speech.speakImmediately(confirmation, language: chosen);

    // Give audio 1200ms to announce before screen transitions
    await _cancellableDelay(const Duration(milliseconds: 1200));

    // Release native volume interception before leaving
    await _volumeKeys.disableInterception();

    if (!mounted) return;

    if (widget.isFirstLaunch) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.of(context).pop(chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeLang = _languages[_selectedIndex];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => _confirmSelection(detail: 'double_tap_screen'),
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyRepeatEvent) {
                // Strictly prevent accidental repeated navigation on long presses
                return KeyEventResult.handled;
              }
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                    event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
                  _cycleSelection(1);
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                    event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
                  _cycleSelection(-1);
                  return KeyEventResult.handled;
                } else if (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space ||
                    event.logicalKey == LogicalKeyboardKey.power) {
                  _confirmSelection(detail: 'hardware_confirm');
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Accessible header badge & replay button
                  Semantics(
                    header: true,
                    label: 'Language Selection. Voice First and Accessible.',
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceHighlight,
                            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                            border: Border.all(color: AppTheme.primary, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.hearing, size: 18, color: AppTheme.primary),
                              SizedBox(width: 8),
                              Text(
                                'VOICE & VOLUME CONTROL',
                                style: TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Replay Options Button
                        Semantics(
                          button: true,
                          label: 'Replay language options spoken out loud',
                          child: InkWell(
                            onTap: _startWalkthroughAnnouncement,
                            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                                border: Border.all(color: AppTheme.borderSubtle),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isAnnouncing ? Icons.volume_up : Icons.replay,
                                    size: 18,
                                    color: _isAnnouncing
                                        ? AppTheme.primary
                                        : AppTheme.textPrimary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'REPLAY',
                                    style: TextStyle(
                                      color: _isAnnouncing
                                          ? AppTheme.primary
                                          : AppTheme.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Large high-contrast title & guidance
                  Semantics(
                    header: true,
                    child: const Text(
                      'Choose Language\nभाषा चुनें • ಭಾಷೆ ಆಯ್ಕೆ',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Tactile hardware instruction box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Column(
                      children: const [
                        Row(
                          children: [
                            Icon(Icons.unfold_more, color: AppTheme.primary, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Volume Up: Next • Volume Down: Previous (Circular)',
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.touch_app, color: AppTheme.primaryLight, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Confirm: Hold volume key, press both, or double-tap screen',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: AppTheme.textMuted, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Android restricts Power key to OS lock; use volume chord or long-press.',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Language Option Cards
                  for (int index = 0; index < _languages.length; index++) ...[
                    _buildLanguageCard(index),
                    const SizedBox(height: 12),
                  ],

                  const SizedBox(height: 8),

                  // Prominent confirmation button
                  Semantics(
                    button: true,
                    label:
                        'Confirm and select ${activeLang.nativeName} (${activeLang.englishName}). Double tap to proceed.',
                    child: ElevatedButton(
                      onPressed: () => _confirmSelection(detail: 'screen_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 28,
                            color: Colors.black,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'CONFIRM ${activeLang.englishName.toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Subtext hint
                  const Text(
                    'Tip: Press both volume buttons together or double-tap screen anytime to confirm.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageCard(int index) {
    final lang = _languages[index];
    final isSelected = index == _selectedIndex;

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '${lang.nativeName}, ${lang.englishName}. ${isSelected ? "Currently selected." : "Double tap or use volume buttons to select."}',
      child: InkWell(
        onTap: () {
          if (isSelected) {
            _confirmSelection(detail: 'tap_selected');
          } else {
            setState(() => _selectedIndex = index);
            _cycleSelection(0);
          }
        },
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.surfaceHighlight : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.borderSubtle,
              width: isSelected ? 3.0 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // High-contrast radio circle
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppTheme.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : AppTheme.textMuted,
                    width: 2.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check,
                        size: 22,
                        color: Colors.black,
                      )
                    : null,
              ),
              const SizedBox(width: 18),
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
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Option ${index + 1} • ${lang.englishName}',
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.volume_up,
                    size: 22,
                    color: Colors.black,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
