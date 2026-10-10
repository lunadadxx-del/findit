import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/app_language.dart';
import '../models/target_objects.dart';
import '../services/assistant_service.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';
import 'finder_screen.dart';

/// Screen 2 — Modern, Accessible Object Catalog & Selection Screen
///
/// Features:
/// - Prominent voice selection button with pulsing state animation.
/// - Live instant search filtering across supported everyday objects.
/// - Tactile, high-contrast cards with large touch targets.
/// - Honest, immediate guidance when an unsupported item is requested.
class ObjectSelectionScreen extends StatefulWidget {
  const ObjectSelectionScreen({super.key});

  @override
  State<ObjectSelectionScreen> createState() => _ObjectSelectionScreenState();
}

class _ObjectSelectionScreenState extends State<ObjectSelectionScreen>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final SpeechService _speech = SpeechService();
  final TextEditingController _textController = TextEditingController();
  final SettingsService _settings = SettingsService.instance;
  final LocalizationService _l10n = LocalizationService.instance;

  bool _isListening = false;
  bool _speechAvailable = false;
  String _statusText = 'Say an object or tap from the catalog below';
  String _searchQuery = '';
  late AnimationController _pulseController;

  AppLanguage get _lang => _settings.preferredLanguage;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
          lowerBound: 0.95,
          upperBound: 1.15,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _pulseController.reverse();
          } else if (status == AnimationStatus.dismissed && _isListening) {
            _pulseController.forward();
          }
        });

    _initVoice();
  }

  Future<void> _initVoice() async {
    final langResult = await _speech.initialize(language: _lang);
    if (langResult != null && !langResult.isSupported && _lang != AppLanguage.english) {
      _settings.setPreferredLanguage(AppLanguage.english);
    }
    try {
      final status = await Permission.microphone.status;
      if (!status.isGranted) {
        await Permission.microphone.request();
      }
      _speechAvailable = await _speechToText.initialize(
        onError: (_) {
          if (mounted) {
            setState(() {
              _isListening = false;
              _pulseController.stop();
            });
          }
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted && _isListening) {
              setState(() {
                _isListening = false;
                _pulseController.stop();
              });
            }
          }
        },
      );
    } catch (_) {
      _speechAvailable = false;
    }

    if (mounted) {
      _speech.speak(
        'What would you like to find? Tap the microphone, or choose an object.',
      );
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _speechToText.stop();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        setState(() {
          _statusText =
              'Microphone permission denied. Please select an object below.';
        });
        _speech.speak(
          'Microphone unavailable. Please select an object from the list.',
        );
        return;
      }
      _speechAvailable = await _speechToText.initialize();
    }

    if (_isListening) {
      await _speechToText.stop();
      setState(() {
        _isListening = false;
        _pulseController.stop();
      });
      return;
    }

    setState(() {
      _isListening = true;
      _statusText = 'Listening... Say e.g. "Find my bottle"';
    });
    _pulseController.forward();
    _speech.speak('Listening.');

    try {
      await _speechToText.listen(
        onResult: (result) {
          final words = result.recognizedWords;
          if (mounted) {
            setState(() {
              _statusText = 'Heard: "$words"';
            });
          }
          if (result.finalResult && words.isNotEmpty) {
            _handleVoiceInput(words);
          }
        },
        // ignore: deprecated_member_use
        localeId: _lang.locale,
        // ignore: deprecated_member_use
        listenFor: const Duration(seconds: 5),
        // ignore: deprecated_member_use
        pauseFor: const Duration(seconds: 3),
      );
    } catch (_) {
      setState(() {
        _isListening = false;
        _pulseController.stop();
      });
    }
  }

  Future<void> _handleVoiceInput(String transcript) async {
    setState(() {
      _isListening = false;
      _pulseController.stop();
    });

    final res = await AssistantService.instance.processUserInput(
      transcript,
      language: _lang,
    );

    if (res.isUnsupported) {
      final msg = res.spokenReply ?? _l10n.unsupportedObject(_lang);
      setState(() => _statusText = msg);
      _speech.speak(msg, urgent: true);
      return;
    }

    if (res.intent == AssistantIntent.findObject && res.target != null) {
      _launchFinder(res.target!);
      return;
    }

    const notFoundMsg = 'Object not recognized. Choose from the catalog below.';
    setState(() => _statusText = notFoundMsg);
    _speech.speak(notFoundMsg);
  }

  void _launchFinder(String friendlyName) {
    _speech.stop();
    _speechToText.stop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FinderScreen(initialTarget: friendlyName),
      ),
    );
  }

  Future<void> _onManualSubmit(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    final res = await AssistantService.instance.processUserInput(
      trimmed,
      language: _lang,
    );

    if (res.isUnsupported) {
      final msg = res.spokenReply ?? _l10n.unsupportedObject(_lang);
      setState(() => _statusText = msg);
      _speech.speak(msg, urgent: true);
      return;
    }

    if (res.intent == AssistantIntent.findObject && res.target != null) {
      _launchFinder(res.target!);
      return;
    }

    final msg = 'Target "$trimmed" not in supported object list. Choose below.';
    setState(() => _statusText = msg);
    _speech.speak(msg);
  }

  @override
  Widget build(BuildContext context) {
    final allKeys = TargetObjects.supported.keys.toList();
    final filteredKeys = _searchQuery.isEmpty
        ? allKeys
        : allKeys.where((k) {
            final localized = _l10n.objectName(k, _lang).toLowerCase();
            final english = k.toLowerCase();
            final q = _searchQuery.toLowerCase();
            return localized.contains(q) || english.contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
          tooltip: 'Back to home',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Select Target Object'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Voice Selection Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(
                    color: _isListening ? AppTheme.error : AppTheme.primary,
                    width: 1.8,
                  ),
                ),
                child: Column(
                  children: [
                    // Status live region
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _isListening
                              ? AppTheme.error
                              : AppTheme.primaryLight,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Mic button
                    Semantics(
                      button: true,
                      label: _isListening
                          ? 'Stop listening'
                          : 'Start voice search. Say what you want to find',
                      child: ScaleTransition(
                        scale: _pulseController,
                        child: GestureDetector(
                          onTap: _startListening,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isListening
                                  ? AppTheme.listening
                                  : AppTheme.primary,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (_isListening
                                              ? AppTheme.listening
                                              : AppTheme.primary)
                                          .withValues(alpha: 0.4),
                                  blurRadius: 24,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              color: Colors.black,
                              size: 52,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isListening
                          ? 'LISTENING... (TAP TO STOP)'
                          : 'TAP TO SPEAK',
                      style: TextStyle(
                        color: _isListening
                            ? AppTheme.error
                            : AppTheme.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Search Filter Text Field
              TextField(
                controller: _textController,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 17,
                ),
                decoration: InputDecoration(
                  hintText: 'Filter catalog (e.g. bottle, phone)...',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.primary,
                  ),
                  suffixIcon: _textController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: AppTheme.textMuted,
                          ),
                          onPressed: () {
                            setState(() {
                              _textController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                onSubmitted: _onManualSubmit,
              ),
              const SizedBox(height: 24),

              // Catalog Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'SUPPORTED OBJECTS (${filteredKeys.length})',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const Text(
                    '100% Reliable Offline',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Filtered Objects Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.35,
                ),
                itemCount: filteredKeys.length,
                itemBuilder: (context, index) {
                  final friendlyName = filteredKeys[index];
                  final icon = TargetObjects.iconFor(friendlyName);
                  final localized = _l10n.objectName(friendlyName, _lang);
                  final capitalized =
                      localized[0].toUpperCase() + localized.substring(1);

                  return Semantics(
                    button: true,
                    label: 'Select $localized',
                    child: InkWell(
                      onTap: () => _launchFinder(friendlyName),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                          border: Border.all(
                            color: AppTheme.borderSubtle,
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.borderSubtle,
                                ),
                              ),
                              child: Icon(
                                icon,
                                color: AppTheme.primary,
                                size: 28,
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  capitalized,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  friendlyName[0].toUpperCase() +
                                      friendlyName.substring(1),
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Honesty Note Card (Explaining keys/wallet unsupported)
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
                      Icons.info_outline_rounded,
                      color: AppTheme.telemetry,
                      size: 22,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Looking for keys, wallet, or glasses? Mobile neural models cannot reliably resolve them without high false alarms. FindIt honestly tells you instead of guessing.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
