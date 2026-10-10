import 'dart:async';
import 'package:flutter/material.dart';

import '../services/assistant_service.dart';
import '../services/localization_service.dart';
import '../services/lost_phone_service.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';
import 'finder_screen.dart';

/// Screen for managing Lost Phone Mode.
///
/// Features:
/// - Tactile toggle to turn on/off.
/// - Clarifies battery-conscious duty cycle (auto-timeout).
/// - Big prominent STOP ALARM banner when triggered.
/// - Audio and tactile feedback.
class LostPhoneScreen extends StatefulWidget {
  const LostPhoneScreen({super.key});

  @override
  State<LostPhoneScreen> createState() => _LostPhoneScreenState();
}

class _LostPhoneScreenState extends State<LostPhoneScreen> {
  final LostPhoneService _lostPhone = LostPhoneService.instance;
  final SpeechService _speech = SpeechService();

  int _selectedTimeout = 20; // Default 20 minutes
  bool _isLoading = false;
  StreamSubscription<String>? _triggerSub;
  StreamSubscription<void>? _stopSub;
  StreamSubscription<String>? _irisWakeupSub;
  StreamSubscription<String>? _commandSub;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    _lostPhone.initialize();
    _speech.initialize();

    _triggerSub = _lostPhone.onTriggerDetected.listen((phrase) {
      if (mounted) {
        _speech.speak('Lost Phone alarm triggered. Phone located.', urgent: true);
      }
    });

    _stopSub = _lostPhone.onAlarmStopped.listen((_) {
      if (mounted) {
        final lang = SettingsService.instance.preferredLanguage;
        _speech.speak(
          LocalizationService.instance.alarmSilenced(lang),
          urgent: true,
        );
      }
    });

    _irisWakeupSub = _lostPhone.onIrisWakeup.listen((phrase) {
      // Prompt is voiced natively by LostPhoneService to avoid audio collisions
    });

    _commandSub = _lostPhone.onVoiceCommand.listen((command) async {
      if (!mounted) return;
      final lang = SettingsService.instance.preferredLanguage;
      final res = await AssistantService.instance.processUserInput(command, language: lang);

      if (res.isUnsupported) {
        final msg = res.spokenReply ?? LocalizationService.instance.unsupportedObject(lang);
        _speech.speak(msg, urgent: true);
        return;
      }

      if (res.intent == AssistantIntent.findObject && res.target != null) {
        final phrase = LocalizationService.instance.searchingTarget(
          res.target!,
          lang,
        );
        _speech.speak(phrase, urgent: true);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => FinderScreen(initialTarget: res.target!),
          ),
        );
        return;
      }

      if (res.intent == AssistantIntent.lostPhone) {
        final phrase = LocalizationService.instance.lostPhoneAlert(lang);
        _speech.speak(phrase, urgent: true);
        return;
      }

      if (res.spokenReply != null) {
        _speech.speak(res.spokenReply!, urgent: true);
      }
    });

    _errorSub = _lostPhone.onErrorOccurred.listen((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppTheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _triggerSub?.cancel();
    _stopSub?.cancel();
    _irisWakeupSub?.cancel();
    _commandSub?.cancel();
    _errorSub?.cancel();
    _speech.stop();
    super.dispose();
  }

  Future<void> _toggleLostPhoneMode() async {
    setState(() => _isLoading = true);
    if (_lostPhone.isRunning) {
      final success = await _lostPhone.stopLostPhoneMode();
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _speech.speak('Lost Phone Mode disabled. Microphone turned off.');
        }
      }
    } else {
      final success = await _lostPhone.startLostPhoneMode(
        timeoutMinutes: _selectedTimeout,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _speech.speak(
            'Lost Phone Mode active. Listening for Hey Iris. Auto shut off in $_selectedTimeout minutes.',
            urgent: true,
          );
        } else if (_lostPhone.lastError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_lostPhone.lastError!),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _stopAlarm() async {
    await _lostPhone.stopAlarm();
  }

  Future<void> _testAlarm() async {
    await _lostPhone.testAlarm();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _lostPhone,
      builder: (context, _) {
        final isRunning = _lostPhone.isRunning;
        final isAlarm = _lostPhone.isAlarmRinging;

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            title: const Text('Lost Phone Mode'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // ALARM TRIGGERED ACTIVE BANNER
                if (isAlarm) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.error.withValues(alpha: 0.5),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '🚨 PHONE FOUND! 🚨',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Heard: "${_lostPhone.triggeredPhrase ?? "Hey Iris"}"\nAlarm & vibration are sounding at maximum volume.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _stopAlarm,
                            icon: const Icon(Icons.volume_off_rounded, size: 26),
                            label: const Text(
                              'SILENCE ALARM',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppTheme.error,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // MAIN STATUS CARD
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(
                      color: isRunning ? AppTheme.success : AppTheme.borderSubtle,
                      width: isRunning ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isRunning
                                    ? Icons.mic_rounded
                                    : Icons.mic_off_outlined,
                                color: isRunning
                                    ? AppTheme.success
                                    : AppTheme.textMuted,
                                size: 28,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                isRunning ? 'MODE ACTIVE' : 'MODE DISABLED',
                                style: TextStyle(
                                  color: isRunning
                                      ? AppTheme.success
                                      : AppTheme.textMuted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          if (_isLoading)
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          else
                            Switch(
                              value: isRunning,
                              activeThumbColor: AppTheme.success,
                              onChanged: (_) => _toggleLostPhoneMode(),
                            ),
                        ],
                      ),
                      const Divider(color: AppTheme.borderSubtle, height: 24),
                      Text(
                        isRunning
                          ? 'Listening for "Hey Iris"...'
                          : 'Microphone is OFF',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isRunning
                            ? 'A persistent notification is running. If you misplace your phone, say "Hey Iris" or "Find my phone" to sound the loud alert.'
                            : 'To prevent battery drain and preserve privacy, the microphone is kept OFF during normal app use. Turn this mode on before setting your phone down.',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _toggleLostPhoneMode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isRunning
                                ? AppTheme.error
                                : AppTheme.primary,
                            foregroundColor: isRunning
                                ? Colors.white
                                : Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            isRunning
                                ? 'TURN OFF LOST PHONE MODE'
                                : 'ENABLE LOST PHONE MODE',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // BATTERY CONSCIOUS AUTO-TIMEOUT CARD
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.battery_saver_rounded,
                            color: AppTheme.primaryLight,
                            size: 24,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Battery-Conscious Auto-Shutoff',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Continuous microphone recording uses battery power. FindIt automatically stops listening after this duration to prevent draining your battery.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        children: [10, 20, 30, 45].map((mins) {
                          final isSelected = _selectedTimeout == mins;
                          return ChoiceChip(
                            label: Text(
                              '$mins min${mins == 20 ? ' (rec)' : ''}',
                              style: TextStyle(
                                color: isSelected ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: AppTheme.primary,
                            backgroundColor: AppTheme.surfaceElevated,
                            onSelected: isRunning
                                ? null
                                : (selected) {
                                    if (selected) {
                                      setState(() => _selectedTimeout = mins);
                                    }
                                  },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // QUICK TEST ALARM
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Test Alert Sound & Vibration',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Verify that the alarm volume and vibration cadence are easily audible in your room.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _testAlarm,
                        icon: const Icon(Icons.volume_up_rounded, color: AppTheme.primaryLight),
                        label: const Text(
                          'PLAY TEST ALARM (MAX VOLUME)',
                          style: TextStyle(
                            color: AppTheme.primaryLight,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primaryLight),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ANDROID POLICY & RESTRICTIONS NOTICE
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: AppTheme.textSecondary, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Android Restrictions & Hotword Details',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Text(
                        '• Trigger phrases: "Hey Iris", "Iris", or "Find my phone".\n'
                        '• Compliant Foreground Service: Uses an official Android microphone foreground service with a persistent status notification.\n'
                        '• Background Restrictions: On Android 14+ / 16, OEM battery savers (like Funtouch/Vivo/Xiaomi) may suspend background audio if the phone enters deep sleep (Doze mode). For maximum reliability, leave FindIt open before stepping away.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
