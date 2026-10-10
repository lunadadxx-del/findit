import 'package:vibration/vibration.dart';
import 'guidance_engine.dart';
import 'settings_service.dart';

/// Haptic proximity feedback using Android vibrator APIs.
///
/// Features:
/// - Distinct vibration intervals: slower when far, rapid when near.
/// - Double-tap pulse when very close.
/// - Triumphant triple-pulse cadence upon finding the object.
/// - Respects user preferences in [SettingsService].
/// - Fails gracefully if device does not support vibration.
class HapticService {
  bool _hasVibrator = false;

  Future<void> initialize() async {
    try {
      _hasVibrator = await Vibration.hasVibrator();
    } catch (_) {
      _hasVibrator = false;
    }
  }

  bool get isAvailable => _hasVibrator;

  /// Proximity pulse.
  Future<void> proximityTick(Proximity proximity) async {
    if (!_hasVibrator || !SettingsService.instance.hapticFeedback) return;
    try {
      switch (proximity) {
        case Proximity.far:
          await Vibration.vibrate(duration: 40);
          break;
        case Proximity.approaching:
          await Vibration.vibrate(duration: 65);
          break;
        case Proximity.close:
          await Vibration.vibrate(duration: 90);
          break;
        case Proximity.veryClose:
          // Rapid double pulse
          await Vibration.vibrate(duration: 70);
          await Future.delayed(const Duration(milliseconds: 80));
          await Vibration.vibrate(duration: 70);
          break;
      }
    } catch (_) {}
  }

  /// Celebratory triple-pulse sequence when the object is confirmed found.
  Future<void> foundCelebration() async {
    if (!_hasVibrator || !SettingsService.instance.hapticFeedback) return;
    try {
      for (final ms in [100, 100, 250]) {
        await Vibration.vibrate(duration: ms);
        await Future.delayed(const Duration(milliseconds: 140));
      }
    } catch (_) {}
  }

  /// Gentle notification when target enters camera field of view.
  Future<void> acquired() async {
    if (!_hasVibrator || !SettingsService.instance.hapticFeedback) return;
    try {
      await Vibration.vibrate(duration: 50);
    } catch (_) {}
  }

  /// Subtle double-tap when target leaves the frame.
  Future<void> lost() async {
    if (!_hasVibrator || !SettingsService.instance.hapticFeedback) return;
    try {
      await Vibration.vibrate(duration: 35);
      await Future.delayed(const Duration(milliseconds: 60));
      await Vibration.vibrate(duration: 35);
    } catch (_) {}
  }

  /// Tactile feedback when cycling language options with hardware volume buttons.
  Future<void> selectionTick() async {
    try {
      await Vibration.vibrate(duration: 45);
    } catch (_) {}
  }

  /// Confirm feedback pattern when language selection is confirmed.
  Future<void> confirmed() async {
    try {
      await Vibration.vibrate(pattern: [0, 80, 80, 160]);
    } catch (_) {}
  }
}
