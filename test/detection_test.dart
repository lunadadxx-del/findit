import 'dart:typed_data';

import 'package:findit/models/detection.dart';
import 'package:findit/models/target_objects.dart';
import 'package:findit/services/detection_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a uniform YUV420 frame: every Y pixel = [y], every UV pair = [uv].
({Uint8List y, Uint8List u, Uint8List v}) uniformFrame(
  int width,
  int height,
  int y,
  int uv,
) {
  final yBytes = Uint8List(width * height)..fillRange(0, width * height, y);
  final uvW = (width / 2).ceil();
  final uvH = (height / 2).ceil();
  final uBytes = Uint8List(uvW * uvH)..fillRange(0, uvW * uvH, uv);
  final vBytes = Uint8List(uvW * uvH)..fillRange(0, uvW * uvH, uv);
  return (y: yBytes, u: uBytes, v: vBytes);
}

void main() {
  group('yuv420ToRgb300', () {
    test('white frame converts to near-white RGB', () {
      final f = uniformFrame(64, 48, 255, 128);
      final rgb = yuv420ToRgb300(
        y: f.y,
        u: f.u,
        v: f.v,
        width: 64,
        height: 48,
        uvRowStride: 32,
        uvPixelStride: 1,
        rotation: 0,
      );
      expect(rgb.length, 300 * 300 * 3);
      // Sample a few pixels; all channels should be ~255.
      for (final i in [0, 1000, 50000, 269997]) {
        expect(rgb[i], greaterThan(240), reason: 'channel at $i');
      }
    });

    test('black frame converts to near-black RGB', () {
      final f = uniformFrame(64, 48, 0, 128);
      final rgb = yuv420ToRgb300(
        y: f.y,
        u: f.u,
        v: f.v,
        width: 64,
        height: 48,
        uvRowStride: 32,
        uvPixelStride: 1,
        rotation: 0,
      );
      for (final i in [0, 1000, 50000, 269997]) {
        expect(rgb[i], lessThan(16), reason: 'channel at $i');
      }
    });

    test('pure-red YUV converts to dominant red channel', () {
      // BT.601 for (255,0,0): Y≈76, U≈84, V≈255.
      final yBytes = Uint8List(64 * 48)..fillRange(0, 64 * 48, 76);
      final uBytes = Uint8List(32 * 24)..fillRange(0, 32 * 24, 84);
      final vBytes = Uint8List(32 * 24)..fillRange(0, 32 * 24, 255);
      final rgb = yuv420ToRgb300(
        y: yBytes,
        u: uBytes,
        v: vBytes,
        width: 64,
        height: 48,
        uvRowStride: 32,
        uvPixelStride: 1,
        rotation: 0,
      );
      final r = rgb[0], g = rgb[1], b = rgb[2];
      expect(r, greaterThan(200));
      expect(g, lessThan(60));
      expect(b, lessThan(60));
    });

    test('rotation 90 maps a marker pixel to the expected quadrant', () {
      // 4x2 landscape frame, rotation 90 (CW) -> 2x4 upright portrait.
      // Source top-right pixel (3,0) maps under CW rotation to upright
      // (x'=1/2, y'=3/4): middle horizontally, lower vertically.
      // In the 300x300 target that is tx~150, ty~262.
      const w = 4, h = 2;
      final yBytes = Uint8List(w * h); // all black
      yBytes[0 * w + 3] = 255; // source (3,0) white
      final uBytes = Uint8List(2 * 1)..fillRange(0, 2, 128);
      final vBytes = Uint8List(2 * 1)..fillRange(0, 2, 128);
      final rgb = yuv420ToRgb300(
        y: yBytes,
        u: uBytes,
        v: vBytes,
        width: w,
        height: h,
        uvRowStride: 2,
        uvPixelStride: 1,
        rotation: 90,
      );
      // Scan the upright 300x300 for the bright pixel's neighborhood.
      int brightCount = 0;
      int brightTxSum = 0, brightTySum = 0;
      for (int ty = 0; ty < 300; ty++) {
        for (int tx = 0; tx < 300; tx++) {
          final i = (ty * 300 + tx) * 3;
          if (rgb[i] > 200) {
            brightCount++;
            brightTxSum += tx;
            brightTySum += ty;
          }
        }
      }
      expect(brightCount, greaterThan(0));
      final cx = brightTxSum / brightCount; // expect ~150 (middle)
      final cy = brightTySum / brightCount; // expect ~262 (lower area)
      expect(cx, greaterThan(100));
      expect(cx, lessThan(200));
      expect(cy, greaterThan(220));
      expect(cy, lessThan(295));
    });
    test('yuv420ToRgb300 supports custom yRowStride padding', () {
      const w = 4, h = 2, strideY = 6;
      final yBytes = Uint8List(strideY * h);
      // Row 0: 4 pixels white, 2 pixels padding (black)
      yBytes[0] = 255;
      yBytes[1] = 255;
      yBytes[2] = 255;
      yBytes[3] = 255;
      // Row 1: 4 pixels white, 2 pixels padding
      yBytes[strideY + 0] = 255;
      yBytes[strideY + 1] = 255;
      yBytes[strideY + 2] = 255;
      yBytes[strideY + 3] = 255;

      final uBytes = Uint8List(2 * 1)..fillRange(0, 2, 128);
      final vBytes = Uint8List(2 * 1)..fillRange(0, 2, 128);
      final rgb = yuv420ToRgb300(
        y: yBytes,
        u: uBytes,
        v: vBytes,
        width: w,
        height: h,
        uvRowStride: 2,
        uvPixelStride: 1,
        rotation: 0,
        yRowStride: strideY,
      );
      expect(rgb.length, 300 * 300 * 3);
      expect(rgb[0], greaterThan(240));
    });
  });

  group('parseDetections label mapping & postprocess', () {
    final labels = [
      '???',
      'person',
      'bicycle',
      'car',
      'motorcycle',
      'airplane',
      'bus',
      'train',
      'truck',
      'boat',
      'traffic light',
      'fire hydrant',
      '???',
      'stop sign',
      'parking meter',
      'bench',
      'bird',
      'cat',
      'dog',
      'horse',
      'sheep',
      'cow',
      'elephant',
      'bear',
      'zebra',
      'giraffe',
      '???',
      'backpack',
      'umbrella',
      '???',
      '???',
      'handbag',
      'tie',
      'suitcase',
      'frisbee',
      'skis',
      'snowboard',
      'sports ball',
      'kite',
      'baseball bat',
      'baseball glove',
      'skateboard',
      'surfboard',
      'tennis racket',
      'bottle',
      '???',
      'wine glass',
      'cup',
      'fork',
      'knife',
      'spoon',
      'bowl',
      'banana',
      'apple',
      'sandwich',
      'orange',
      'broccoli',
      'carrot',
      'hot dog',
      'pizza',
      'donut',
      'cake',
      'chair',
      'couch',
      'potted plant',
      'bed',
      '???',
      'dining table',
      '???',
      '???',
      'toilet',
      '???',
      'tv',
      'laptop',
      'mouse',
      'remote',
      'keyboard',
      'cell phone',
      'microwave',
      'oven',
      'toaster',
      'sink',
      'refrigerator',
      '???',
      'book',
      'clock',
      'vase',
      'scissors',
      'teddy bear',
      'hair drier',
      'toothbrush',
    ];

    test('correctly maps 0-based TFLite PostProcess class index to labelmap', () {
      // cls 43 = bottle (COCO id 44, labelmap index 44)
      // cls 76 = cell phone (COCO id 77, labelmap index 77)
      // cls 0 = person (COCO id 1, labelmap index 1)
      // cls 46 = cup (COCO id 47, labelmap index 47)
      final boxes = [
        [0.1, 0.2, 0.8, 0.6],
        [0.0, 0.0, 0.5, 0.5],
        [0.2, 0.3, 0.7, 0.8],
        [0.3, 0.4, 0.6, 0.7],
      ];
      final classes = [43.0, 76.0, 0.0, 46.0];
      final scores = [0.88, 0.75, 0.92, 0.65];

      final dets = parseDetections(
        boxes: boxes,
        classes: classes,
        scores: scores,
        count: 4,
        labels: labels,
        threshold: 0.40,
      );

      expect(dets.length, 4);
      expect(dets[0][0], 'bottle');
      expect(dets[0][1], 0.88);
      expect(dets[1][0], 'cell phone');
      expect(dets[2][0], 'person');
      expect(dets[3][0], 'cup');
    });

    test('filters out detections below threshold', () {
      final boxes = [
        [0.1, 0.2, 0.8, 0.6],
      ];
      final classes = [43.0];
      final scores = [0.35];

      final dets = parseDetections(
        boxes: boxes,
        classes: classes,
        scores: scores,
        count: 1,
        labels: labels,
        threshold: 0.40,
      );

      expect(dets, isEmpty);
    });

    test('ignores background placeholder labels', () {
      // Suppose model outputs a class pointing to '???'
      final boxes = [
        [0.1, 0.2, 0.8, 0.6],
      ];
      final classes = [11.0]; // 11 + 1 = 12 ('???')
      final scores = [0.90];

      final dets = parseDetections(
        boxes: boxes,
        classes: classes,
        scores: scores,
        count: 1,
        labels: labels,
        threshold: 0.40,
      );

      expect(dets, isEmpty);
    });
  });

  group('Detection.fromWire', () {
    test('round-trips isolate wire format', () {
      final d = Detection.fromWire(['bottle', 0.83, 0.1, 0.2, 0.5, 0.9]);
      expect(d.label, 'bottle');
      expect(d.confidence, closeTo(0.83, 0.001));
      expect(d.centerX, closeTo(0.3, 0.001));
      expect(d.centerY, closeTo(0.55, 0.001));
      expect(d.area, closeTo(0.4 * 0.7, 0.001));
    });
  });

  group('TargetObjects', () {
    test('supported targets map to model labels', () {
      expect(TargetObjects.modelLabelFor('phone'), 'cell phone');
      expect(TargetObjects.modelLabelFor('bag'), 'handbag');
      expect(TargetObjects.isSupported('keys'), isFalse);
      expect(TargetObjects.unsupported, contains('keys'));
    });

    test('voice input matching', () {
      expect(TargetObjects.matchVoiceInput('find my bottle please'), 'bottle');
      expect(TargetObjects.matchVoiceInput('where is my mobile'), 'phone');
      expect(TargetObjects.matchVoiceInput('find my keys'), isNull);
      expect(TargetObjects.matchVoiceInput('hello world'), isNull);
    });

    test('unsupported query detection', () {
      expect(TargetObjects.isQueryUnsupported('where are my keys'), isTrue);
      expect(TargetObjects.isQueryUnsupported('find my wallet please'), isTrue);
      expect(
        TargetObjects.isQueryUnsupported('can you see spectacles'),
        isTrue,
      );
      expect(TargetObjects.isQueryUnsupported('find my bottle'), isFalse);
    });

    test('icon mapping provides valid icons', () {
      expect(TargetObjects.iconFor('bottle'), isNotNull);
      expect(TargetObjects.iconFor('phone'), isNotNull);
      expect(TargetObjects.iconFor('unknown_object'), isNotNull);
    });
  });
}
