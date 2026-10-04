import 'package:vibration/vibration.dart';

import 'guidance_engine.dart';

/// Proximity feedback through vibration.
///
/// The closer the target, the faster the pulse — a blind user can feel
/// themselves homing in without looking at the screen. A distinct
/// celebration pattern marks the found state.
///
/// All calls are safe no-ops on devices without a vibrator.
class HapticService {
  bool _hasVibrator = false;

  Future<void> initialize() async {
    try {
      _hasVibrator = await Vibration.hasVibrator();
    } catch (_) {
      _hasVibrator = false;
    }
  }

  /// One short pulse whose rate encodes proximity. Call at most ~2x/sec;
  /// the finder screen throttles this.
  Future<void> proximityTick(Proximity proximity) async {
    if (!_hasVibrator) return;
    try {
      switch (proximity) {
        case Proximity.far:
          await Vibration.vibrate(duration: 40);
          break;
        case Proximity.approaching:
          await Vibration.vibrate(duration: 60);
          break;
        case Proximity.close:
          await Vibration.vibrate(duration: 80);
          break;
        case Proximity.veryClose:
          // Double-tap: unmistakably close.
          await Vibration.vibrate(duration: 60);
          await Future.delayed(const Duration(milliseconds: 90));
          await Vibration.vibrate(duration: 60);
          break;
      }
    } catch (_) {}
  }

  /// Unmistakable "found" pattern: three rising pulses.
  Future<void> foundCelebration() async {
    if (!_hasVibrator) return;
    try {
      for (final ms in [80, 80, 160]) {
        await Vibration.vibrate(duration: ms);
        await Future.delayed(const Duration(milliseconds: 120));
      }
    } catch (_) {}
  }

  /// Gentle tick when the target first appears after being lost.
  Future<void> acquired() async {
    if (!_hasVibrator) return;
    try {
      await Vibration.vibrate(duration: 50);
    } catch (_) {}
  }
}
