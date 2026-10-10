import 'package:flutter/material.dart';

import '../models/detection.dart';
import '../theme/app_theme.dart';

/// Draws high-contrast, accessible targeting reticles over the camera preview.
///
/// Target objects receive a prominent reticle with corner brackets and a high-contrast
/// telemetry tag. Non-target items are subtly outlined for spatial awareness without distraction.
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.detections,
    required this.targetModelLabel,
    this.isTargetLocked = false,
  });

  final List<Detection> detections;
  final String? targetModelLabel;
  final bool isTargetLocked;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DetectionPainter(
        detections: detections,
        targetModelLabel: targetModelLabel,
        isTargetLocked: isTargetLocked,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  _DetectionPainter({
    required this.detections,
    required this.targetModelLabel,
    required this.isTargetLocked,
  });

  final List<Detection> detections;
  final String? targetModelLabel;
  final bool isTargetLocked;

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in detections) {
      final isTarget = d.label == targetModelLabel;

      final rect = Rect.fromLTRB(
        (d.left * size.width).clamp(0.0, size.width),
        (d.top * size.height).clamp(0.0, size.height),
        (d.right * size.width).clamp(0.0, size.width),
        (d.bottom * size.height).clamp(0.0, size.height),
      );

      if (rect.width <= 0 || rect.height <= 0) continue;

      if (isTarget) {
        _drawTargetReticle(canvas, rect, d);
      } else {
        _drawSecondaryObject(canvas, rect, d);
      }
    }
  }

  void _drawTargetReticle(Canvas canvas, Rect rect, Detection d) {
    final reticleColor = isTargetLocked ? AppTheme.success : AppTheme.primary;

    // 1. Subtle semi-transparent bounding tint
    final tintPaint = Paint()
      ..color = reticleColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      tintPaint,
    );

    // 2. High-contrast main contour
    final strokePaint = Paint()
      ..color = reticleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      strokePaint,
    );

    // 3. Prominent Corner Brackets (HUD style for fast optical identification)
    final bracketPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    final double cornerArm = (rect.width * 0.22).clamp(16.0, 32.0);

    // Top-Left
    canvas.drawLine(
      rect.topLeft,
      Offset(rect.left + cornerArm, rect.top),
      bracketPaint,
    );
    canvas.drawLine(
      rect.topLeft,
      Offset(rect.left, rect.top + cornerArm),
      bracketPaint,
    );

    // Top-Right
    canvas.drawLine(
      rect.topRight,
      Offset(rect.right - cornerArm, rect.top),
      bracketPaint,
    );
    canvas.drawLine(
      rect.topRight,
      Offset(rect.right, rect.top + cornerArm),
      bracketPaint,
    );

    // Bottom-Left
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left + cornerArm, rect.bottom),
      bracketPaint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      Offset(rect.left, rect.bottom - cornerArm),
      bracketPaint,
    );

    // Bottom-Right
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right - cornerArm, rect.bottom),
      bracketPaint,
    );
    canvas.drawLine(
      rect.bottomRight,
      Offset(rect.right, rect.bottom - cornerArm),
      bracketPaint,
    );

    // 4. Center Target Crosshair Node
    final center = rect.center;
    final nodePaint = Paint()
      ..color = reticleColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 5.0, nodePaint);

    // 5. Telemetry Pill Label above or inside box
    final percent = (d.confidence * 100).round();
    final labelText = '${d.label.toUpperCase()} · $percent%';

    final tp = TextPainter(
      text: TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelWidth = tp.width + 18;
    final labelHeight = tp.height + 8;
    final labelLeft = rect.left.clamp(
      8.0,
      (rect.right - labelWidth).clamp(8.0, double.infinity),
    );
    final labelTop = (rect.top - labelHeight - 6) >= 40.0
        ? (rect.top - labelHeight - 6)
        : (rect.top + 8);

    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(labelLeft, labelTop, labelWidth, labelHeight),
      const Radius.circular(8),
    );

    final bgPaint = Paint()..color = reticleColor;
    canvas.drawRRect(pillRect, bgPaint);
    tp.paint(canvas, Offset(labelLeft + 9, labelTop + 4));
  }

  void _drawSecondaryObject(Canvas canvas, Rect rect, Detection d) {
    // Subtle contour for background items
    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      strokePaint,
    );

    // Small subtle tag
    final percent = (d.confidence * 100).round();
    final tp = TextPainter(
      text: TextSpan(
        text: ' ${d.label} $percent% ',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.8),
          backgroundColor: Colors.black.withValues(alpha: 0.6),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final labelTop = (rect.top - tp.height - 2).clamp(0.0, double.infinity);
    tp.paint(canvas, Offset(rect.left, labelTop));
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter old) =>
      old.detections != detections ||
      old.targetModelLabel != targetModelLabel ||
      old.isTargetLocked != isTargetLocked;
}
