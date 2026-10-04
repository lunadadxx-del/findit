import 'package:findit/models/detection.dart';
import 'package:findit/services/guidance_engine.dart';
import 'package:findit/services/object_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

Detection _box(
  String label,
  double l,
  double t,
  double r,
  double b, [
  double conf = 0.8,
]) => Detection(
  label: label,
  confidence: conf,
  left: l,
  top: t,
  right: r,
  bottom: b,
);

void main() {
  group('ObjectTracker', () {
    test('picks most confident detection when no history', () {
      final t = ObjectTracker();
      final d = t.update([
        _box('bottle', 0.1, 0.1, 0.3, 0.3, 0.5),
        _box('bottle', 0.5, 0.5, 0.7, 0.7, 0.9),
      ], 'bottle');
      expect(d, isNotNull);
      expect(d!.confidence, 0.9);
      expect(t.hasTarget, isTrue);
    });

    test('ignores other labels', () {
      final t = ObjectTracker();
      final d = t.update([_box('cup', 0.1, 0.1, 0.3, 0.3)], 'bottle');
      expect(d, isNull);
      expect(t.hasTarget, isFalse);
    });

    test('smooths jitter across frames', () {
      final t = ObjectTracker();
      t.update([_box('bottle', 0.20, 0.20, 0.40, 0.40)], 'bottle');
      final d = t.update([_box('bottle', 0.30, 0.30, 0.50, 0.50)], 'bottle');
      // EMA with 0.45: 0.20 + (0.30-0.20)*0.45 = 0.245
      expect(d!.left, closeTo(0.245, 0.001));
    });

    test('survives a few missed frames then drops', () {
      final t = ObjectTracker();
      t.update([_box('bottle', 0.2, 0.2, 0.4, 0.4)], 'bottle');
      for (var i = 0; i < ObjectTracker.maxMisses - 1; i++) {
        expect(t.update([], 'bottle'), isNotNull);
      }
      expect(t.update([], 'bottle'), isNull);
      expect(t.isLost, isTrue);
    });

    test('matches by overlap, not just confidence', () {
      final t = ObjectTracker();
      t.update([_box('bottle', 0.1, 0.1, 0.3, 0.3, 0.9)], 'bottle');
      // Slightly moved box (high IoU) with lower confidence vs far box
      // with higher confidence: tracker should prefer the overlap.
      final d = t.update([
        _box('bottle', 0.12, 0.12, 0.32, 0.32, 0.5),
        _box('bottle', 0.7, 0.7, 0.9, 0.9, 0.99),
      ], 'bottle');
      expect(d!.left, lessThan(0.5));
    });
  });

  group('GuidanceEngine', () {
    GuidanceEngine engine() => GuidanceEngine(targetFriendlyName: 'bottle');

    test('lost when nothing tracked', () {
      final g = engine().guide(null);
      expect(g.isLost, isTrue);
      expect(g.isFound, isFalse);
    });

    test('says left when target is left', () {
      final g = engine().guide(_box('bottle', 0.05, 0.3, 0.25, 0.6));
      expect(g.zone, HorizontalZone.left);
      expect(g.phrase.toLowerCase(), contains('left'));
    });

    test('says right when target is right', () {
      final g = engine().guide(_box('bottle', 0.75, 0.3, 0.95, 0.6));
      expect(g.zone, HorizontalZone.right);
      expect(g.phrase.toLowerCase(), contains('right'));
    });

    test('found when big and centered', () {
      final g = engine().guide(_box('bottle', 0.25, 0.25, 0.75, 0.75));
      expect(g.isFound, isTrue);
      expect(g.phrase.toLowerCase(), contains('found'));
    });

    test('not found when big but off-center', () {
      final g = engine().guide(_box('bottle', 0.55, 0.25, 0.95, 0.75));
      expect(g.isFound, isFalse);
    });

    test('proximity scales with box area', () {
      final e = engine();
      expect(
        e.guide(_box('bottle', 0.45, 0.4, 0.55, 0.5)).proximity,
        Proximity.far,
      );
      expect(
        e.guide(_box('bottle', 0.35, 0.3, 0.65, 0.7)).proximity,
        Proximity.close,
      );
    });
  });
}
