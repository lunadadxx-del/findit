import '../models/app_language.dart';
import '../models/detection.dart';
import 'localization_service.dart';

/// Where the target is, horizontally, in the camera view.
enum HorizontalZone { left, slightlyLeft, center, slightlyRight, right }

/// How close the target appears, from its relative box size.
/// This is a visual proximity heuristic (bounding box area), not a metric depth sensor.
enum Proximity { far, approaching, close, veryClose }

/// Guidance state machine conforming to PRD Section 14.
enum GuidanceState {
  searching,
  detected,
  tracking,
  guiding,
  closer,
  near,
  found,
  lost,
  reacquiring,
}

/// One guidance decision: what to tell the user right now.
class Guidance {
  const Guidance({
    required this.state,
    required this.zone,
    required this.proximity,
    required this.isFound,
    required this.isLost,
    required this.phrase,
    this.isUncertain = false,
  });

  final GuidanceState state;
  final HorizontalZone zone;
  final Proximity proximity;
  final bool isFound;
  final bool isLost;
  final bool isUncertain;

  /// Spoken guidance phrase (localized).
  final String phrase;

  static const lost = Guidance(
    state: GuidanceState.lost,
    zone: HorizontalZone.center,
    proximity: Proximity.far,
    isFound: false,
    isLost: true,
    phrase: 'I lost the object. Move the camera slowly.',
  );
}

/// Turns a tracked detection box into voice and haptic guidance for blind navigation.
///
/// Implements the full PRD state machine:
/// SEARCHING -> DETECTED -> TRACKING -> GUIDING -> CLOSER -> NEAR -> FOUND
/// and recovery: TRACKING -> LOST -> REACQUIRING -> TRACKING
///
/// Pure Dart — no Flutter dependencies, fully unit-testable.
class GuidanceEngine {
  /// Box area above which the target counts as found (fills a significant chunk
  /// of the frame and is roughly centered).
  static const double foundArea = 0.20;

  GuidanceEngine({
    required this.targetFriendlyName,
    this.language = AppLanguage.english,
  });

  final String targetFriendlyName;
  AppLanguage language;

  GuidanceState _state = GuidanceState.searching;
  Proximity? _previousProximity;
  int _consecutiveTrackedFrames = 0;
  int _consecutiveMissedFrames = 0;

  GuidanceState get currentState => _state;

  void reset() {
    _state = GuidanceState.searching;
    _previousProximity = null;
    _consecutiveTrackedFrames = 0;
    _consecutiveMissedFrames = 0;
  }

  Guidance guide(Detection? tracked, {bool isCandidateUncertain = false}) {
    final l10n = LocalizationService.instance;

    // Handle uncertainty: confidence is marginal / ambiguous
    if (isCandidateUncertain && _state != GuidanceState.found) {
      return Guidance(
        state: GuidanceState.searching,
        zone: HorizontalZone.center,
        proximity: Proximity.far,
        isFound: false,
        isLost: false,
        isUncertain: true,
        phrase: l10n.scanningUncertain(targetFriendlyName, language),
      );
    }

    if (tracked == null) {
      _previousProximity = null;
      _consecutiveTrackedFrames = 0;
      _consecutiveMissedFrames++;

      if (_state == GuidanceState.found) {
        // Keep found status once attained
        return Guidance(
          state: GuidanceState.found,
          zone: HorizontalZone.center,
          proximity: Proximity.veryClose,
          isFound: true,
          isLost: false,
          phrase: l10n.stopObjectFound(targetFriendlyName, language),
        );
      }

      // If we were tracking, enter reacquiring first to prevent sudden jarring lost alerts
      if (_state == GuidanceState.tracking ||
          _state == GuidanceState.guiding ||
          _state == GuidanceState.closer ||
          _state == GuidanceState.near ||
          _state == GuidanceState.reacquiring) {
        if (_consecutiveMissedFrames < 3) {
          _state = GuidanceState.reacquiring;
          return Guidance(
            state: GuidanceState.reacquiring,
            zone: HorizontalZone.center,
            proximity: Proximity.far,
            isFound: false,
            isLost: false,
            phrase: l10n.reacquiring(language),
          );
        }
      }

      _state = GuidanceState.lost;
      return Guidance(
        state: GuidanceState.lost,
        zone: HorizontalZone.center,
        proximity: Proximity.far,
        isFound: false,
        isLost: true,
        phrase: l10n.objectLost(language),
      );
    }

    // Detection exists
    _consecutiveMissedFrames = 0;
    _consecutiveTrackedFrames++;

    final cx = tracked.centerX;
    final cy = tracked.centerY;
    final area = tracked.area;

    // Horizontal zone mapping
    final HorizontalZone zone;
    if (cx < 0.28) {
      zone = HorizontalZone.left;
    } else if (cx < 0.42) {
      zone = HorizontalZone.slightlyLeft;
    } else if (cx <= 0.58) {
      zone = HorizontalZone.center;
    } else if (cx <= 0.72) {
      zone = HorizontalZone.slightlyRight;
    } else {
      zone = HorizontalZone.right;
    }

    // Proximity classification based on normalized bounding box area
    final Proximity proximity;
    if (area < 0.025) {
      proximity = Proximity.far;
    } else if (area < 0.07) {
      proximity = Proximity.approaching;
    } else if (area < 0.17) {
      proximity = Proximity.close;
    } else {
      proximity = Proximity.veryClose;
    }

    // State transition progression
    if (_state == GuidanceState.searching ||
        _state == GuidanceState.lost ||
        _state == GuidanceState.reacquiring) {
      _state = GuidanceState.detected;
    } else if (_consecutiveTrackedFrames == 2) {
      _state = GuidanceState.tracking;
    } else {
      _state = GuidanceState.guiding;
    }

    // Found condition: sufficiently large and well-centered in frame
    final isCentered = cx > 0.28 && cx < 0.72 && cy > 0.20 && cy < 0.85;
    if (area >= foundArea && isCentered) {
      _state = GuidanceState.found;
      _previousProximity = proximity;
      return Guidance(
        state: GuidanceState.found,
        zone: zone,
        proximity: proximity,
        isFound: true,
        isLost: false,
        phrase: l10n.stopObjectFound(targetFriendlyName, language),
      );
    }

    // Directional guidance and closer/near progression
    final gettingCloser =
        _previousProximity != null &&
        proximity.index > _previousProximity!.index;
    _previousProximity = proximity;

    final String phrase;
    if (zone == HorizontalZone.center) {
      if (area >= 0.14) {
        _state = GuidanceState.near;
        phrase = l10n.objectIsClose(language);
      } else if (gettingCloser) {
        _state = GuidanceState.closer;
        phrase = l10n.youAreGettingCloser(language);
      } else {
        phrase = l10n.moveForward(language);
      }
    } else if (zone == HorizontalZone.slightlyLeft) {
      phrase = l10n.moveSlightlyLeft(language);
    } else if (zone == HorizontalZone.left) {
      phrase = l10n.moveLeft(language);
    } else if (zone == HorizontalZone.slightlyRight) {
      phrase = l10n.moveSlightlyRight(language);
    } else {
      phrase = l10n.moveRight(language);
    }

    return Guidance(
      state: _state,
      zone: zone,
      proximity: proximity,
      isFound: false,
      isLost: false,
      phrase: phrase,
    );
  }
}
