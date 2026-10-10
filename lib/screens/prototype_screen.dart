import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/detection.dart';
import '../models/target_objects.dart';
import '../services/detection_service.dart';
import '../widgets/detection_overlay.dart';

/// Phase 2 prototype: proves the real detection pipeline end to end.
///
/// Camera preview + live on-device detections drawn as boxes + a target
/// picker + a status line. No guidance yet (Phase 4), no polish (Phase 6) —
/// this screen exists to verify that DETECTION actually works on a phone.
class PrototypeScreen extends StatefulWidget {
  const PrototypeScreen({super.key});

  @override
  State<PrototypeScreen> createState() => _PrototypeScreenState();
}

class _PrototypeScreenState extends State<PrototypeScreen> {
  CameraController? _camera;
  final DetectionService _detections = DetectionService();
  StreamSubscription<DetectionFrame>? _sub;

  String _status = 'Starting…';
  List<Detection> _latest = const [];
  int _inferenceMs = 0;
  String _targetFriendly = 'bottle';
  DateTime _lastSubmit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _failed = false;

  String get _targetModelLabel =>
      TargetObjects.modelLabelFor(_targetFriendly) ?? '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        setState(() {
          _failed = true;
          _status = 'Camera permission denied — FindIt cannot scan without it.';
        });
        return;
      }

      setState(() => _status = 'Loading on-device model…');
      await _detections.initialize();
      await _detections.ready;

      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _camera = controller;

      _sub = _detections.results.listen(_onResults);

      setState(() => _status = 'Scanning… point at objects.');
      await controller.startImageStream(_onImage);
    } catch (e) {
      setState(() {
        _failed = true;
        _status = 'Startup failed: $e';
      });
    }
  }

  /// Throttled: at most one frame every 300ms, and the service itself
  /// drops frames while the isolate is busy.
  void _onImage(CameraImage image) {
    final now = DateTime.now();
    if (now.difference(_lastSubmit).inMilliseconds < 300) return;
    _lastSubmit = now;

    final camera = _camera;
    if (camera == null) return;
    try {
      final y = image.planes[0];
      final u = image.planes[1];
      final v = image.planes[2];
      _detections.submitFrame(
        y: y.bytes,
        u: u.bytes,
        v: v.bytes,
        width: image.width,
        height: image.height,
        uvRowStride: u.bytesPerRow,
        uvPixelStride: u.bytesPerPixel ?? 1,
        rotation: camera.description.sensorOrientation,
      );
    } catch (_) {
      // A malformed frame must never kill the stream.
    }
  }

  void _onResults(DetectionFrame frame) {
    if (!mounted) return;
    final target = _targetModelLabel;
    final hits = frame.detections.where((d) => d.label == target).toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    setState(() {
      _latest = frame.detections;
      _inferenceMs = frame.inferenceMs;
      _status = hits.isEmpty
          ? 'Scanning for $_targetFriendly… (${frame.detections.length} other objects seen)'
          : 'TARGET $_targetFriendly: ${(hits.first.confidence * 100).round()}% (${hits.length} found)';
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _camera?.stopImageStream();
    _camera?.dispose();
    _detections.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('FindIt · Detection prototype'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _failed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _status,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: camera == null || !camera.value.isInitialized
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.amber),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            AspectRatio(
                              aspectRatio: camera.value.aspectRatio,
                              child: CameraPreview(camera),
                            ),
                            DetectionOverlay(
                              detections: _latest,
                              targetModelLabel: _targetModelLabel,
                            ),
                          ],
                        ),
                ),
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _status,
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'inference ${_inferenceMs}ms · ${_latest.length} detections',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'TARGET OBJECT',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: TargetObjects.supported.keys.map((name) {
                          final selected = name == _targetFriendly;
                          return ChoiceChip(
                            label: Text(
                              name,
                              style: const TextStyle(fontSize: 16),
                            ),
                            selected: selected,
                            selectedColor: Colors.amber,
                            onSelected: (_) =>
                                setState(() => _targetFriendly = name),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
