import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/app_language.dart';
import '../models/target_objects.dart';
import '../services/assistant_service.dart';
import '../services/localization_service.dart';
import '../services/settings_service.dart';
import '../services/lost_phone_service.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';
import 'finder_screen.dart';
import 'lost_phone_screen.dart';
import 'object_selection_screen.dart';
import 'settings_screen.dart';

/// Screen 1 — Modern, Accessible Home Screen
///
/// Features:
/// - Prominent, accessible voice search control with pulsing animation.
/// - Clear greeting and instructions.
/// - High-contrast, tactile cards for all supported objects directly accessible.
/// - Manual search input as accessible fallback.
/// - Seamless TalkBack screen reader support.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final SpeechService _speech = SpeechService();
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final SettingsService _settings = SettingsService.instance;
  final LostPhoneService _lostPhone = LostPhoneService.instance;
  final LocalizationService _l10n = LocalizationService.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isListening = false;
  bool _speechAvailable = false;
  String _statusText = 'Tap the microphone or say "Find my bottle"';
  late AnimationController _pulseController;
  StreamSubscription<void>? _lostPhoneStoppedSub;
  StreamSubscription<String>? _irisWakeupSub;
  StreamSubscription<String>? _voiceCommandSub;

  AppLanguage get _lang => _settings.preferredLanguage;
  String get _name => _settings.userName;

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

    _lostPhone.initialize();
    _lostPhoneStoppedSub = _lostPhone.onAlarmStopped.listen((_) {
      if (mounted) {
        final lang = _speech.currentLanguage;
        _speech.speak(_l10n.alarmSilenced(lang), urgent: true);
      }
    });

    _irisWakeupSub = _lostPhone.onIrisWakeup.listen((phrase) {
      if (mounted) {
        final greeting = _l10n.howCanIHelp(_lang);
        setState(() => _statusText = greeting);
        // Spoken prompt and microphone reply listening are handled seamlessly
        // by the foreground service to prevent audio pipeline collisions.
      }
    });

    _voiceCommandSub = _lostPhone.onVoiceCommand.listen((command) {
      if (mounted && command.isNotEmpty) {
        if (ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        _handleVoiceInput(command);
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
      final mic = await Permission.microphone.status;
      if (!mic.isGranted) {
        await Permission.microphone.request();
      }
      _speechAvailable = await _speechToText.initialize();
    } catch (_) {
      _speechAvailable = false;
    }

    final activeLang = _speech.currentLanguage;
    final greeting = _name.isNotEmpty
        ? '${_l10n.welcomeGreeting(activeLang)} ${_l10n.niceToMeetYou(_name, activeLang)} ${_l10n.howCanIHelp(activeLang)}'
        : '${_l10n.welcomeGreeting(activeLang)} ${_l10n.howCanIHelp(activeLang)}';

    // Warm spoken announcement on launch
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _speech.speak(greeting);
      }
    });
  }

  @override
  void dispose() {
    _lostPhoneStoppedSub?.cancel();
    _irisWakeupSub?.cancel();
    _voiceCommandSub?.cancel();
    _speech.stop();
    _speechToText.stop();
    _pulseController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleVoiceSearch() async {
    if (_isListening) {
      await _speechToText.stop();
      setState(() {
        _isListening = false;
        _pulseController.stop();
      });
      return;
    }

    if (!_speechAvailable) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        setState(() {
          _statusText = 'Microphone permission required for voice search.';
        });
        _speech.speak(
          'Microphone unavailable. Please select an object manually.',
        );
        return;
      }
      _speechAvailable = await _speechToText.initialize();
    }

    setState(() {
      _isListening = true;
      _statusText = 'Listening... Say "Find my bottle"';
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
      await _speech.speak(msg, urgent: true);
      return;
    }

    if (res.intent == AssistantIntent.findObject && res.target != null) {
      final target = res.target!;
      final phrase = _l10n.searchingTarget(target, _lang);
      setState(() => _statusText = phrase);
      await _speech.speak(phrase, urgent: true);

      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        _navigateToFinder(target);
      });
      return;
    }

    if (res.intent == AssistantIntent.describeSurroundings) {
      _showDescribeSurroundingsDialog();
      return;
    }

    if (res.intent == AssistantIntent.settings) {
      _navigateToSettings();
      return;
    }

    if (res.intent == AssistantIntent.help) {
      _showHelpDialog();
      return;
    }

    if (res.intent == AssistantIntent.irisWakeup) {
      final msg = res.spokenReply ?? _l10n.howCanIHelp(_lang);
      setState(() => _statusText = msg);
      await _speech.speak(msg, urgent: true);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted && !_isListening) {
          _toggleVoiceSearch();
        }
      });
      return;
    }

    if (res.intent == AssistantIntent.lostPhone) {
      final msg = _lang == AppLanguage.hindi
          ? 'खोया फोन मोड। अलार्म बजाया जा रहा है।'
          : 'Lost Phone Mode. Sounding alert.';
      setState(() => _statusText = msg);
      await _speech.speak(msg, urgent: true);
      await _lostPhone.testAlarm();
      _navigateToLostPhone();
      return;
    }

    final fallback = res.spokenReply ?? 'Object not recognized. Choose from the catalog below.';
    setState(() => _statusText = fallback);
    _speech.speak(fallback, urgent: true);
  }

  void _navigateToLostPhone() {
    _speech.stop();
    _speechToText.stop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LostPhoneScreen()),
    );
  }

  void _navigateToFinder(String target) {
    _speech.stop();
    _speechToText.stop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FinderScreen(initialTarget: target)),
    );
  }

  void _navigateToSettings() {
    _speech.stop();
    _speechToText.stop();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _showDescribeSurroundingsDialog() {
    const msg =
        'Surroundings Description: Point your camera at a room. FindIt scans and guides you to visible objects.';
    _speech.speak(msg);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Describe Surroundings'),
        content: const Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _navigateToFinder('bottle');
            },
            child: const Text('OPEN SCANNER'),
          ),
        ],
      ),
    );
  }

  void _showSavedObjectsDialog() {
    const msg =
        'My Saved Objects: In future versions, you can save custom labels like "My water bottle" or "My desk keys". This feature is currently in preview.';
    _speech.speak('My Saved Objects is an upcoming feature in preview.');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('My Saved Objects'),
        content: const Text(msg),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    _speech.speak(
      'FindIt helps you locate everyday objects. Say what you want to find, point the camera around, and follow voice directions and vibration cues.',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How FindIt Works'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                '1. Tell FindIt what you need: Say "Find my bottle" or tap any object card.\n\n'
                '2. Hold your phone up and pan around slowly.\n\n'
                '3. Follow audio instructions: "Move left", "Move forward", "Getting closer".\n\n'
                '4. Follow vibration pulses: Haptics beat faster as you get closer to the object.\n\n'
                '5. "Stop. Object found." confirms the object is right by your hands!\n\n'
                '• 100% On-Device: Runs offline without sending camera data anywhere.',
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('GOT IT'),
          ),
        ],
      ),
    );
  }

  void _onManualSearchSubmit(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _handleVoiceInput(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final supportedKeys = TargetObjects.supported.keys.toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.explore_rounded,
                color: Colors.black,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            const Text('FindIt'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'How FindIt works',
            onPressed: _showHelpDialog,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings and accessibility',
            onPressed: _navigateToSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _lostPhone,
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ACTIVE ALARM BANNER
                  if (_lostPhone.isAlarmRinging) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.error,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.notifications_active_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '🚨 PHONE FOUND! ALARM RINGING 🚨',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => _lostPhone.stopAlarm(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppTheme.error,
                              ),
                              child: const Text(
                                'SILENCE ALARM',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Greeting & Instruction
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
                    Text(
                      _name.isNotEmpty
                          ? 'Welcome, $_name'
                          : 'Find Everyday Objects',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tap the microphone to speak, or tap any object below to start camera tracking.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Voice Search Hero Card
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(
                    color: _isListening ? AppTheme.error : AppTheme.primary,
                    width: 2.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening ? AppTheme.error : AppTheme.primary)
                          .withValues(alpha: 0.15),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Status Speech Pill
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _isListening
                              ? AppTheme.listening.withValues(alpha: 0.3)
                              : AppTheme.background,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusFull,
                          ),
                          border: Border.all(
                            color: _isListening
                                ? AppTheme.error
                                : AppTheme.borderSubtle,
                          ),
                        ),
                        child: Text(
                          _statusText,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _isListening
                                ? AppTheme.textPrimary
                                : AppTheme.primaryLight,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Big Pulse Mic Button
                    Semantics(
                      button: true,
                      label: _isListening
                          ? 'Stop listening'
                          : 'Tap to speak what you want to find',
                      child: ScaleTransition(
                        scale: _pulseController,
                        child: GestureDetector(
                          onTap: _toggleVoiceSearch,
                          child: Container(
                            width: 120,
                            height: 120,
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
                                          .withValues(alpha: 0.45),
                                  blurRadius: 30,
                                  spreadRadius: 6,
                                ),
                              ],
                            ),
                            child: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              color: Colors.black,
                              size: 64,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _isListening
                          ? 'LISTENING... (TAP TO STOP)'
                          : 'TAP TO SPEAK (OR SAY "FIND MY PHONE")',
                      style: TextStyle(
                        color: _isListening
                            ? AppTheme.error
                            : AppTheme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Fallback Manual Text Input
              TextField(
                controller: _searchController,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'Or type object name (e.g. bottle, cup)...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppTheme.primary,
                    ),
                    onPressed: () =>
                        _onManualSearchSubmit(_searchController.text),
                  ),
                ),
                onSubmitted: _onManualSearchSubmit,
              ),
              const SizedBox(height: 20),

              // Lost Phone Mode Quick Action Card
              Container(
                decoration: BoxDecoration(
                  color: _lostPhone.isRunning
                      ? AppTheme.surfaceHighlight
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(
                    color: _lostPhone.isRunning
                        ? AppTheme.success
                        : AppTheme.borderSubtle,
                    width: _lostPhone.isRunning ? 2 : 1,
                  ),
                ),
                child: InkWell(
                  onTap: _navigateToLostPhone,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _lostPhone.isRunning
                                ? AppTheme.success.withValues(alpha: 0.2)
                                : AppTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _lostPhone.isRunning
                                ? Icons.mic_rounded
                                : Icons.phone_android_rounded,
                            color: _lostPhone.isRunning
                                ? AppTheme.success
                                : AppTheme.primary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Lost Phone Mode',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_lostPhone.isRunning) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.success,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _lostPhone.isRunning
                                    ? 'Listening for "Hey Iris" (persistent notification running)'
                                    : 'Mic OFF normally. Tap to enable "Hey Iris" alarm detection',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: AppTheme.textMuted,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Section Header: Supported Objects
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'QUICK TAP TO FIND',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _speech.stop();
                      _speechToText.stop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ObjectSelectionScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.grid_view_rounded, size: 16),
                    label: const Text('View All'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryLight,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 2-Column Responsive Accessible Objects Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.45,
                ),
                itemCount: supportedKeys.length,
                itemBuilder: (context, index) {
                  final key = supportedKeys[index];
                  final icon = TargetObjects.iconFor(key);
                  final localized = _l10n.objectName(key, _lang);
                  final capitalized =
                      localized[0].toUpperCase() + localized.substring(1);

                  return Semantics(
                    button: true,
                    label: 'Find $localized',
                    child: InkWell(
                      onTap: () => _navigateToFinder(key),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      child: Container(
                        padding: const EdgeInsets.all(14),
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceElevated,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppTheme.borderSubtle,
                                    ),
                                  ),
                                  child: Icon(
                                    icon,
                                    color: AppTheme.primary,
                                    size: 24,
                                  ),
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: AppTheme.textMuted,
                                  size: 14,
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  capitalized,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_lang != AppLanguage.english)
                                  Text(
                                    key[0].toUpperCase() + key.substring(1),
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

              // Secondary Actions Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showDescribeSurroundingsDialog,
                        icon: const Icon(Icons.explore_outlined, size: 20),
                        label: const Text('Surroundings'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showSavedObjectsDialog,
                        icon: const Icon(
                          Icons.bookmark_border_rounded,
                          size: 20,
                        ),
                        label: const Text('Saved Items'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Offline Privacy Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.shield_outlined,
                      color: AppTheme.success,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      '100% On-Device Neural Model • Offline & Private',
                      style: TextStyle(
                        color: AppTheme.successLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    ),
  ),
);
  }
}
