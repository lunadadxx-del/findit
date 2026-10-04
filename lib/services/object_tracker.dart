import '../models/detection.dart';

/// Tracks one selected target across detection frames.
///
/// Detections flicker: the model may miss the target for a frame or two,
/// and boxes jitter. The tracker keeps a smoothed box (exponential moving
/// average) and matches new detections to the previous box by IoU, so the
/// guidance doesn't jump around or drop out on a single missed frame.
///
/// Pure Dart — no Flutter dependencies, fully unit-testable.
class ObjectTracker {
  /// Smoothing factor for the box. 0.0 = frozen, 1.0 = no smoothing.
  static const double smoothing = 0.45;

  /// Frames without a matching detection before the target counts as lost.
  static const int maxMisses = 6;

  /// Minimum IoU to consider a detection the same object as the tracked one.
  static const double minIou = 0.15;

  Detection? _tracked;
  int _misses = 0;
  int _framesTracked = 0;

  Detection? get tracked => _tracked;
  bool get hasTarget => _tracked != null;
  bool get isLost => _tracked == null && _misses >= maxMisses;
  int get framesTracked => _framesTracked;

  void reset() {
    _tracked = null;
    _misses = 0;
    _framesTracked = 0;
  }

  /// Feed one frame of detections for [targetLabel] (the exact model label).
  /// Returns the current smoothed tracked box, or null when nothing is
  /// tracked right now.
  Detection? update(List<Detection> detections, String targetLabel) {
    final candidates =
        detections.where((d) => d.label == targetLabel).toList();
    if (candidates.isEmpty) {
      _misses++;
      if (_misses >= maxMisses) _tracked = null;
      return _tracked;
    }

    Detection best;
    final prev = _tracked;
    if (prev == null) {
      // No history: take the most confident detection.
      candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
      best = candidates.first;
    } else {
      // Match by overlap with the previous box; fall back to the most
      // confident candidate when nothing overlaps (object may have moved
      // fast, or the previous box was wrong).
      Detection? overlapBest;
      double overlapBestIou = minIou;
      for (final c in candidates) {
        final iou = _iou(prev, c);
        if (iou > overlapBestIou) {
          overlapBestIou = iou;
          overlapBest = c;
        }
      }
      if (overlapBest != null) {
        best = overlapBest;
      } else {
        candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
        best = candidates.first;
      }
    }

    _misses = 0;
    _framesTracked++;
    if (prev == null) {
      _tracked = best;
    } else {
      // Exponential moving average on each coordinate; confidence is
      // taken fresh so the UI can show the live value.
      _tracked = Detection(
        label: best.label,
        confidence: best.confidence,
        left: _lerp(prev.left, best.left),
        top: _lerp(prev.top, best.top),
        right: _lerp(prev.right, best.right),
        bottom: _lerp(prev.bottom, best.bottom),
      );
    }
    return _tracked;
  }

  static double _lerp(double a, double b) => a + (b - a) * smoothing;

  /// Intersection-over-union of two normalized boxes.
  static double _iou(Detection a, Detection b) {
    final interLeft = a.left > b.left ? a.left : b.left;
    final interTop = a.top > b.top ? a.top : b.top;
    final interRight = a.right < b.right ? a.right : b.right;
    final interBottom = a.bottom < b.bottom ? a.bottom : b.bottom;
    final interW = interRight - interLeft;
    final interH = interBottom - interTop;
    if (interW <= 0 || interH <= 0) return 0.0;
    final inter = interW * interH;
    final union = a.area + b.area - inter;
    return union <= 0 ? 0.0 : inter / union;
  }
}
