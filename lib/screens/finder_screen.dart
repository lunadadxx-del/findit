import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/detection.dart';
import '../models/target_objects.dart';
import '../services/detection_service.dart';
import '../services/guidance_engine.dart';
import '../services/haptic_service.dart';
import '../services/object_tracker.dart';
import '../services/speech_service.dart';
import '../widgets/detection_overlay.dart';

/// FindIt — the working prototype.
///
/// Closed loop: camera → real on-device detection → tracking → direction +
/// proximity guidance → voice + haptics → found.
///
/// Designed for blind and low-vision users: everything important is spoken
/// or felt, the visual preview is secondary. Large touch targets, high
/// contrast, screen-reader labels throughout.
class FinderScreen extends StatefulWidget {
  const FinderScreen({super.key});

  @override
  State<FinderScreen> createState() => _FinderScreenState();
}

class _FinderScreenState extends State<FinderScreen> {
  CameraController? _camera;
  final DetectionService _detections = DetectionService();
  final ObjectTracker _tracker = ObjectTracker();
  final SpeechService _speech = SpeechService();
  final HapticService _haptics = HapticService();
  final stt.SpeechToText _voice = stt.SpeechToText();
  StreamSubscription<DetectionFrame>? _sub;

  GuidanceEngine? _guidance;
  String _targetFriendly = 'bottle';
  List<Detection> _latest = const [];
  Detection? _tracked;
  Guidance _guidanceState = Guidance.lost;

  String _status = 'Starting…';
  bool _failed = false;
  bool _scanning = false;
  bool _found = false;
  bool _listening = false;
  DateTime _lastSubmit = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastHaptic = DateTime.fromMillisecondsSinceEpoch(0);
  bool _wasTracking = false;

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
          _status = 'Camera permission denied. FindIt needs the camera to scan.';
        });
        return;
      }
      final mic = await Permission.microphone.request();
      // Mic is optional (voice input); continue without it if denied.
      if (mic.isGranted) {
        try {
          await _voice.initialize();
        } catch (_) {}
      }

      setState(() => _status = 'Loading on-device model…');
      await _detections.initialize();
      await _detections.ready;
      await _speech.initialize();
      await _haptics.initialize();

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

      _guidance = GuidanceEngine(targetFriendlyName: _targetFriendly);
      setState(() {
        _status = 'Ready. Say what to find, or tap a target below.';
      });
      await _speech.speak(
        'FindIt ready. Tell me what to find, or choose below.',
      );
    } catch (e) {
      setState(() {
        _failed = true;
        _status = 'Startup failed: $e';
      });
    }
  }

  void _onImage(CameraImage image) {
    if (!_scanning) return;
    final now = DateTime.now();
    if (now.difference(_lastSubmit).inMilliseconds < 300) return;
    _lastSubmit = now;
    final camera = _camera;
    if (camera == null) return;
    try {
      final u = image.planes[1];
      _detections.submitFrame(
        y: image.planes[0].bytes,
        u: u.bytes,
        v: image.planes[2].bytes,
        width: image.width,
        height: image.height,
        uvRowStride: u.bytesPerRow,
        uvPixelStride: u.bytesPerPixel ?? 1,
        rotation: camera.description.sensorOrientation,
      );
    } catch (_) {}
  }

  Future<void> _onResults(DetectionFrame frame) async {
    if (!mounted || !_scanning) return;
    final engine = _guidance;
    if (engine == null) return;

    final tracked = _tracker.update(frame.detections, _targetModelLabel);
    final g = engine.guide(tracked);

    // Haptics: pulse rate follows proximity; celebrate on found.
    final now = DateTime.now();
    if (g.isFound && !_found) {
      await _haptics.foundCelebration();
    } else if (tracked != null &&
        now.difference(_lastHaptic).inMilliseconds > 700) {
      _lastHaptic = now;
      await _haptics.proximityTick(g.proximity);
    }
    if (tracked != null && !_wasTracking) {
      await _haptics.acquired();
    }
    _wasTracking = tracked != null;

    // Voice: throttled inside SpeechService; found always interrupts.
    if (g.isFound && !_found) {
      await _speech.speak(g.phrase, urgent: true);
    } else if (!g.isLost) {
      await _speech.speak(g.phrase);
    }

    setState(() {
      _latest = frame.detections;
      _tracked = tracked;
      _guidanceState = g;
      _found = g.isFound;
      _status = g.isFound
          ? 'FOUND your $_targetFriendly!'
          : tracked == null
          ? 'Scanning for $_targetFriendly… move the phone slowly.'
          : g.phrase;
    });

    if (g.isFound) {
      // Pause scanning briefly so the celebration isn't drowned out,
      // then keep tracking in case the user wants to re-find.
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  void _toggleScanning() {
    if (_scanning) {
      setState(() {
        _scanning = false;
        _status = 'Paused. Tap Start to keep looking for $_targetFriendly.';
      });
      _speech.speak('Paused.');
    } else {
      _tracker.reset();
      _found = false;
      setState(() {
        _scanning = true;
        _status = 'Scanning for $_targetFriendly… move the phone slowly.';
      });
      _speech.speak('Looking for your $_targetFriendly. Move the phone slowly.');
      _camera?.startImageStream(_onImage).catchError((_) {});
    }
  }

  void _selectTarget(String friendly) {
    setState(() {
      _targetFriendly = friendly;
      _guidance = GuidanceEngine(targetFriendlyName: friendly);
      _tracker.reset();
      _found = false;
      if (_scanning) {
        _status = 'Scanning for $friendly… move the phone slowly.';
      }
    });
    _speech.speak('Looking for $friendly.');
  }

  Future<void> _listenForTarget() async {
    if (_listening) return;
    if (!await _voice.hasPermission) {
      setState(() => _status = 'Microphone not available — pick a target below.');
      return;
    }
    setState(() => _listening = true);
    try {
      await _voice.listen(
        onResult: (result) {
          if (result.finalResult) {
            final said = result.recognizedWords;
            setState(() => _listening = false);
            final match = TargetObjects.matchVoiceInput(said);
            if (match != null) {
              _selectTarget(match);
            } else {
              final unsupported = TargetObjects.unsupported.any(
                (u) => said.toLowerCase().contains(u),
              );
              final msg =
                  unsupported
                      ? 'Sorry, I cannot detect that yet. Try bottle, cup, book, phone, bag, remote, keyboard, or mouse.'
                      : 'I did not catch that. Try saying "find my phone".';
              setState(() => _status = msg);
              _speech.speak(msg);
            }
          }
        },
        // ignore: deprecated_member_use
        listenFor: const Duration(seconds: 6),
      );
    } catch (_) {
      setState(() => _listening = false);
    }
    // Safety: reset the button if no final result arrives.
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) setState(() => _listening = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _camera?.stopImageStream();
    _camera?.dispose();
    _detections.dispose();
    _speech.dispose();
    _voice.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final g = _guidanceState;
    return Scaffold(
      backgroundColor: Colors.black,
      body:
          _failed
              ? _errorBody()
              : SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Camera preview (secondary for blind users, useful for
                    // sighted helpers). Overlay shows tracked target in amber.
                    Expanded(
                      flex: 3,
                      child:
                          camera == null || !camera.value.isInitialized
                              ? const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.amber,
                                ),
                              )
                              : Stack(
                                fit: StackFit.expand,
                                children: [
                                  CameraPreview(camera),
                                  DetectionOverlay(
                                    detections:
                                        _tracked == null
                                            ? _latest
                                            : [
                                              _tracked!,
                                              ..._latest.where(
                                                (d) =>
                                                    d.label !=
                                                    _targetModelLabel,
                                              ),
                                            ],
                                    targetModelLabel: _targetModelLabel,
                                  ),
                                  if (_found)
                                    Container(
                                      color: Colors.amber.withValues(
                                        alpha: 0.25,
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'FOUND!',
                                          style: TextStyle(
                                            fontSize: 64,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                    ),
                    // Guidance readout — the primary channel.
                    Expanded(
                      flex: 2,
                      child: Container(
                        color:
                            _found
                                ? Colors.amber.shade700
                                : g.isLost
                                ? Colors.grey.shade900
                                : Colors.grey.shade900,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _status,
                                style: TextStyle(
                                  color:
                                      _found ? Colors.black : Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_scanning && !_found)
                              Text(
                                _proximityLabel(g.proximity),
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 18,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Controls: big, high-contrast, screen-reader labelled.
                    Container(
                      color: Colors.black,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  label:
                                      _scanning
                                          ? 'Stop scanning'
                                          : 'Start scanning for $_targetFriendly',
                                  child: ElevatedButton(
                                    onPressed:
                                        camera == null ? null : _toggleScanning,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          _scanning
                                              ? Colors.red.shade700
                                              : Colors.amber,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 20,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    child: Text(
                                      _scanning ? 'STOP' : 'START FINDING',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Semantics(
                                button: true,
                                label: 'Say what to find',
                                child: ElevatedButton(
                                  onPressed: _listenForTarget,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                      horizontal: 20,
                                    ),
                                  ),
                                  child: Icon(
                                    _listening ? Icons.mic : Icons.mic_none,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'OR PICK A TARGET',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              letterSpacing: 2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                TargetObjects.supported.keys.map((name) {
                                  final selected = name == _targetFriendly;
                                  return Semantics(
                                    button: true,
                                    selected: selected,
                                    label: 'Find $name',
                                    child: ChoiceChip(
                                      label: Text(
                                        name,
                                        style: const TextStyle(fontSize: 18),
                                      ),
                                      selected: selected,
                                      selectedColor: Colors.amber,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      onSelected:
                                          (_) => _selectTarget(name),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
    );
  }

  String _proximityLabel(Proximity p) => switch (p) {
    Proximity.far => '○○○○  scanning',
    Proximity.approaching => '●○○○  getting warmer',
    Proximity.close => '●●○○  close',
    Proximity.veryClose => '●●●○  very close!',
  };

  Widget _errorBody() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        _status,
        style: const TextStyle(color: Colors.white, fontSize: 20),
        textAlign: TextAlign.center,
      ),
    ),
  );
}
