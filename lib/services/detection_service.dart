import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../models/detection.dart';
import 'detection_isolate.dart';

/// One batch of detections coming back from the isolate.
class DetectionFrame {
  const DetectionFrame({
    required this.frameId,
    required this.detections,
    required this.inferenceMs,
  });

  final int frameId;
  final List<Detection> detections;
  final int inferenceMs;
}

/// Owns the background detection isolate and exposes a simple API:
///
///   await service.initialize();          // loads model once
///   service.submitFrame(...);            // drops frame if isolate is busy
///   service.results.listen((frame) {...} // detection batches
///   service.dispose();
///
/// Frames are throttled by design: while the isolate is busy, new frames are
/// dropped instead of queued, so guidance latency stays bounded.
class DetectionService {
  Isolate? _isolate;
  SendPort? _isolateInbox;
  ReceivePort? _port;
  final _ready = Completer<void>();
  final _results = StreamController<DetectionFrame>.broadcast();

  int _frameId = 0;
  bool _busy = false;
  bool _disposed = false;

  Stream<DetectionFrame> get results => _results.stream;
  Future<void> get ready => _ready.future;

  Future<void> initialize() async {
    final modelBytes = (await rootBundle.load(
      'assets/models/detect.tflite',
    )).buffer.asUint8List();
    final labelText = await rootBundle.loadString('assets/models/labelmap.txt');
    final labels = labelText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    _port = ReceivePort();
    _port!.listen(_onMessage);
    _isolate = await Isolate.spawn(detectionIsolateEntry, _port!.sendPort);
    // The isolate replies first with its inbox SendPort, then accepts 'init'.
    // We stash init args until the inbox arrives (handled in _onMessage).
    _pendingInit = {'model': modelBytes, 'labels': labels};
  }

  Map<String, Object>? _pendingInit;

  void _onMessage(Object? message) {
    if (message is SendPort) {
      _isolateInbox = message;
      final init = _pendingInit;
      if (init != null) {
        _pendingInit = null;
        _isolateInbox!.send({'type': 'init', ...init});
      }
      return;
    }
    final msg = message as Map<String, Object?>;
    switch (msg['type'] as String) {
      case 'ready':
        if (!_ready.isCompleted) _ready.complete();
      case 'error':
        _busy = false;
      case 'result':
        _busy = false;
        if (_disposed) return;
        final dets = ((msg['dets'] as List).cast<List>())
            .map((w) => Detection.fromWire(w.cast<Object?>()))
            .toList();
        _results.add(
          DetectionFrame(
            frameId: msg['id'] as int,
            detections: dets,
            inferenceMs: msg['ms'] as int,
          ),
        );
    }
  }

  /// Submits one YUV420 frame. Silently drops the frame when the isolate is
  /// still busy — this keeps the pipeline at a steady, bounded latency
  /// instead of building a stale queue.
  ///
  /// Plane bytes are copied: the camera plugin reuses its buffers.
  void submitFrame({
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int width,
    required int height,
    required int uvRowStride,
    required int uvPixelStride,
    required int rotation,
    int? yRowStride,
    double? threshold,
  }) {
    final inbox = _isolateInbox;
    if (inbox == null || _busy || _disposed) return;
    _busy = true;
    _frameId++;
    inbox.send({
      'type': 'frame',
      'id': _frameId,
      'y': Uint8List.fromList(y),
      'u': Uint8List.fromList(u),
      'v': Uint8List.fromList(v),
      'width': width,
      'height': height,
      'yRowStride': yRowStride ?? width,
      'uvRowStride': uvRowStride,
      'uvPixelStride': uvPixelStride,
      'rotation': rotation,
      'threshold': threshold ?? 0.40,
    });
  }

  void dispose() {
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.close();
    _results.close();
  }
}
