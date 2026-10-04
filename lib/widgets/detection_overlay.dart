import 'package:flutter/material.dart';

import '../models/detection.dart';

/// Draws detection boxes over the camera preview.
///
/// Boxes for the currently selected target are drawn amber and thicker;
/// everything else is green. Labels show `name 83%`.
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.detections,
    required this.targetModelLabel,
  });

  final List<Detection> detections;
  final String? targetModelLabel;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DetectionPainter(
        detections: detections,
        targetModelLabel: targetModelLabel,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  _DetectionPainter({required this.detections, required this.targetModelLabel});

  final List<Detection> detections;
  final String? targetModelLabel;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      final isTarget = d.label == targetModelLabel;
      final color = isTarget ? Colors.amber : Colors.greenAccent;
      final paint =
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = isTarget ? 5 : 2.5;

      final rect = Rect.fromLTRB(
        d.left * size.width,
        d.top * size.height,
        d.right * size.width,
        d.bottom * size.height,
      );
      canvas.drawRect(rect, paint);

      final label = '${d.label} ${(d.confidence * 100).round()}%';
      final tp = TextPainter(
        text: TextSpan(
          text: ' $label ',
          style: TextStyle(
            color: Colors.black,
            backgroundColor: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelTop = (rect.top - tp.height - 4).clamp(0.0, size.height);
      tp.paint(canvas, Offset(rect.left, labelTop));
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter old) =>
      old.detections != detections ||
      old.targetModelLabel != targetModelLabel;
}
