/// A single object detection produced by the on-device model.
///
/// Box coordinates are normalized (0.0–1.0) in the *upright* image space —
/// i.e. the image as the user sees it in portrait orientation, after the
/// isolate has applied the camera sensor rotation. (0,0) is top-left.
class Detection {
  const Detection({
    required this.label,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String label;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  /// Decodes a detection sent across the isolate boundary as
  /// `[label, confidence, left, top, right, bottom]`.
  /// Custom class instances cannot cross isolates, so the isolate sends
  /// plain lists and we rebuild them here.
  factory Detection.fromWire(List<Object?> wire) {
    return Detection(
      label: wire[0] as String,
      confidence: (wire[1] as num).toDouble(),
      left: (wire[2] as num).toDouble(),
      top: (wire[3] as num).toDouble(),
      right: (wire[4] as num).toDouble(),
      bottom: (wire[5] as num).toDouble(),
    );
  }

  @override
  String toString() =>
      'Detection($label ${(confidence * 100).toStringAsFixed(0)}% '
      '[${left.toStringAsFixed(2)}, ${top.toStringAsFixed(2)}])';
}
