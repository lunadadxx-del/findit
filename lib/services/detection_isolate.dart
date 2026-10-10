import 'dart:isolate';
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

/// Runs entirely on a background isolate so camera preview never janks.
///
/// Protocol (all messages are plain maps / typed data — custom classes
/// cannot cross isolates):
///
///   main -> isolate: [init] model bytes + labels
///   main -> isolate: [frame] id, Y/U/V planes, dimensions, rotation
///   isolate -> main: [ready]
///   isolate -> main: [result] id, inference ms, detections as
///     [label, confidence, left, top, right, bottom] lists
///
/// Box coordinates are normalized 0..1 in the *upright* image (sensor
/// rotation already applied), matching what the user sees on screen.
void detectionIsolateEntry(SendPort mainPort) {
  final inbox = ReceivePort();
  mainPort.send(inbox.sendPort);

  Interpreter? interpreter;
  List<String>? labels;

  inbox.listen((Object? message) {
    final msg = message as Map<String, Object?>;
    switch (msg['type'] as String) {
      case 'init':
        try {
          interpreter = Interpreter.fromBuffer(msg['model'] as Uint8List);
          labels = (msg['labels'] as List).cast<String>();
          mainPort.send({'type': 'ready'});
        } catch (e) {
          mainPort.send({'type': 'error', 'error': e.toString()});
        }
      case 'frame':
        final it = interpreter;
        final lbs = labels;
        final frameId = msg['id'] as int? ?? 0;
        if (it == null || lbs == null) {
          mainPort.send({
            'type': 'result',
            'id': frameId,
            'ms': 0,
            'dets': <List<Object>>[],
          });
          return;
        }
        try {
          final sw = Stopwatch()..start();
          final rgb = yuv420ToRgb300(
            y: msg['y'] as Uint8List,
            u: msg['u'] as Uint8List,
            v: msg['v'] as Uint8List,
            width: msg['width'] as int,
            height: msg['height'] as int,
            uvRowStride: msg['uvRowStride'] as int,
            uvPixelStride: msg['uvPixelStride'] as int,
            rotation: msg['rotation'] as int,
            yRowStride: msg['yRowStride'] as int?,
          );
          final threshold = (msg['threshold'] as num?)?.toDouble() ?? 0.4;
          final dets = _runInference(it, lbs, rgb, threshold);
          sw.stop();
          mainPort.send({
            'type': 'result',
            'id': frameId,
            'ms': sw.elapsedMilliseconds,
            'dets': dets,
          });
        } catch (e) {
          mainPort.send({
            'type': 'result',
            'id': frameId,
            'ms': 0,
            'dets': <List<Object>>[],
            'error': e.toString(),
          });
        }
    }
  });
}

/// Converts a YUV420 camera frame directly to a 300x300 RGB buffer in one
/// pass, applying the sensor [rotation] (clockwise degrees needed to make
/// the image upright) so the model always sees an upright image.
///
/// Public (not private) so unit tests can verify the conversion math
/// against known YUV colors.
Uint8List yuv420ToRgb300({
  required Uint8List y,
  required Uint8List u,
  required Uint8List v,
  required int width,
  required int height,
  required int uvRowStride,
  required int uvPixelStride,
  required int rotation,
  int? yRowStride,
}) {
  const t = 300;
  final out = Uint8List(t * t * 3);
  final wMinus1 = width - 1;
  final hMinus1 = height - 1;
  final strideY = (yRowStride != null && yRowStride > 0) ? yRowStride : width;
  int oi = 0;

  for (int ty = 0; ty < t; ty++) {
    for (int tx = 0; tx < t; tx++) {
      // Source coordinates as floats, then floor + clamp. (floor, not
      // toInt: toInt truncates toward zero, which is wrong for the
      // negative values the 90/180/270 mappings can produce.)
      double fsx, fsy;
      switch (rotation) {
        case 90:
          fsx = ty * width / t;
          fsy = hMinus1 - tx * height / t;
        case 180:
          fsx = wMinus1 - tx * width / t;
          fsy = hMinus1 - ty * height / t;
        case 270:
          fsx = wMinus1 - ty * width / t;
          fsy = tx * height / t;
        case 0:
        default:
          fsx = tx * width / t;
          fsy = ty * height / t;
      }
      int sx = fsx.floor().clamp(0, wMinus1);
      int sy = fsy.floor().clamp(0, hMinus1);

      final yIndex = (sy * strideY + sx).clamp(0, y.length - 1);
      final yVal = y[yIndex];
      final uvIndex = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;
      final uVal = u[uvIndex.clamp(0, u.length - 1)];
      final vVal = v[uvIndex.clamp(0, v.length - 1)];

      // BT.601 YUV -> RGB, integer math (>>10 == /1024).
      int r = yVal + ((1436 * (vVal - 128)) >> 10);
      int g = yVal - ((352 * (uVal - 128) + 731 * (vVal - 128)) >> 10);
      int b = yVal + ((1815 * (uVal - 128)) >> 10);

      out[oi++] = r < 0 ? 0 : (r > 255 ? 255 : r);
      out[oi++] = g < 0 ? 0 : (g > 255 ? 255 : g);
      out[oi++] = b < 0 ? 0 : (b > 255 ? 255 : b);
    }
  }
  return out;
}

/// Parses raw SSD MobileNet output tensors into normalized detections.
///
/// In TensorFlow Lite's TFLite_Detection_PostProcess operator:
/// - Background is stripped, and classes are 0-based (0 for person, 43 for bottle, etc.).
/// - The COCO label map includes '???' (background) at index 0, so model class `cls`
///   maps to `labels[cls + 1]`.
List<List<Object>> parseDetections({
  required List<List<double>> boxes,
  required List<double> classes,
  required List<double> scores,
  required int count,
  required List<String> labels,
  double threshold = 0.4,
}) {
  final dets = <List<Object>>[];
  final maxBoxes = count > 0 ? count.clamp(0, classes.length) : classes.length;

  for (int i = 0; i < maxBoxes; i++) {
    final score = scores[i];
    if (score < threshold) continue;
    final cls = classes[i].toInt();

    // Map 0-based TFLite_Detection_PostProcess class index to labelmap.txt
    // where index 0 is '???', 1 is 'person', 44 is 'bottle', etc.
    final labelIndex = cls + 1;
    if (labelIndex < 0 || labelIndex >= labels.length) continue;
    final label = labels[labelIndex];
    if (label == '???') continue;

    final box = boxes[i];
    final l = box[1].clamp(0.0, 1.0);
    final t = box[0].clamp(0.0, 1.0);
    final r = box[3].clamp(0.0, 1.0);
    final b = box[2].clamp(0.0, 1.0);
    // SSD order: [ymin, xmin, ymax, xmax] -> wire: [label,conf,l,t,r,b].
    dets.add([label, score, l, t, r, b]);
  }
  return dets;
}

/// Runs the SSD MobileNet model. Input: 300x300x3 uint8 RGB.
/// Outputs: boxes [1,10,4] as [ymin,xmin,ymax,xmax],
/// classes [1,10] (0-based relative to objects), scores [1,10],
/// num_detections [1].
List<List<Object>> _runInference(
  Interpreter interpreter,
  List<String> labels,
  Uint8List rgb, [
  double threshold = 0.4,
]) {
  final input = rgb.reshape([1, 300, 300, 3]);

  final outBoxes = List.filled(40, 0.0).reshape([1, 10, 4]);
  final outClasses = List.filled(10, 0.0).reshape([1, 10]);
  final outScores = List.filled(10, 0.0).reshape([1, 10]);
  final outCount = List.filled(1, 0.0).reshape([1]);

  interpreter.runForMultipleInputs(
    [input],
    {0: outBoxes, 1: outClasses, 2: outScores, 3: outCount},
  );
  final boxes = (outBoxes[0] as List)
      .map((b) => (b as List).cast<double>())
      .toList();
  final classes = (outClasses[0] as List).cast<double>();
  final scores = (outScores[0] as List).cast<double>();
  final count = (outCount[0] is num ? (outCount[0] as num).toInt() : 10)
      .clamp(0, 10);

  return parseDetections(
    boxes: boxes,
    classes: classes,
    scores: scores,
    count: count,
    labels: labels,
    threshold: threshold,
  );
}
