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
      expect(
        TargetObjects.matchVoiceInput('find my bottle please'),
        'bottle',
      );
      expect(TargetObjects.matchVoiceInput('where is my mobile'), 'phone');
      expect(TargetObjects.matchVoiceInput('find my keys'), isNull);
      expect(TargetObjects.matchVoiceInput('hello world'), isNull);
    });
  });
}
