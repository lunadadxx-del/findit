import '../models/detection.dart';

/// Where the target is, horizontally, in the camera view.
enum HorizontalZone { left, center, right }

/// How close the target appears, from its relative box size.
/// This is NOT a metric distance — just "bigger on screen = closer".
enum Proximity { far, approaching, close, veryClose }

/// One guidance decision: what to tell the user right now.
class Guidance {
  const Guidance({
    required this.zone,
    required this.proximity,
    required this.isFound,
    required this.isLost,
    required this.phrase,
  });

  final HorizontalZone zone;
  final Proximity proximity;
  final bool isFound;
  final bool isLost;

  /// Short spoken phrase, e.g. "Bottle, on your left. Move closer."
  final String phrase;

  static const lost = Guidance(
    zone: HorizontalZone.center,
    proximity: Proximity.far,
    isFound: false,
    isLost: true,
    phrase: 'Keep scanning slowly.',
  );
}

/// Turns a tracked box into human guidance.
///
/// Pure Dart — no Flutter dependencies, fully unit-testable.
class GuidanceEngine {
  /// Box area above which the target counts as found (fills a good chunk
  /// of the frame and is roughly centered).
  static const double foundArea = 0.22;

  /// Horizontal dead-zone: inside 0.35–0.65 counts as centered.
  static const double centerMargin = 0.15;

  GuidanceEngine({required this.targetFriendlyName});

  final String targetFriendlyName;

  Guidance guide(Detection? tracked) {
    if (tracked == null) return Guidance.lost;

    final cx = tracked.centerX;
    final zone =
        cx < 0.5 - centerMargin
            ? HorizontalZone.left
            : cx > 0.5 + centerMargin
            ? HorizontalZone.right
            : HorizontalZone.center;

    final area = tracked.area;
    final proximity =
        area < 0.015
            ? Proximity.far
            : area < 0.06
            ? Proximity.approaching
            : area < 0.14
            ? Proximity.close
            : Proximity.veryClose;

    final centered =
        cx > 0.3 && cx < 0.7 && tracked.centerY > 0.25 && tracked.centerY < 0.8;
    if (area >= foundArea && centered) {
      return Guidance(
        zone: zone,
        proximity: proximity,
        isFound: true,
        isLost: false,
        phrase: 'Found it! Your $targetFriendlyName is right in front of you.',
      );
    }

    final name = _cap(targetFriendlyName);
    final where =
        zone == HorizontalZone.left
            ? 'on your left'
            : zone == HorizontalZone.right
            ? 'on your right'
            : 'ahead of you';
    final howFar = switch (proximity) {
      Proximity.far => 'Keep moving the phone slowly.',
      Proximity.approaching => 'Move a little closer.',
      Proximity.close => 'Almost there, keep going.',
      Proximity.veryClose => 'Very close now.',
    };
    return Guidance(
      zone: zone,
      proximity: proximity,
      isFound: false,
      isLost: false,
      phrase: '$name, $where. $howFar',
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
