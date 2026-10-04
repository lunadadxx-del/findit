# FindIt — AI Object Finder for the Visually Impaired

**FindIt helps blind and low-vision users find everyday objects.** Say what you lost (or tap it), point the phone camera around, and FindIt guides you with voice directions and haptic pulses until a "found" celebration.

```
CAMERA → REAL DETECTION → TRACKING → DIRECTION → VOICE/HAPTICS → FOUND
```

Built for the iQOO Grand Finale hackathon.

## What it does

- **Real on-device object detection** — quantized SSD MobileNet V1 (COCO) via TensorFlow Lite, running fully offline on a background isolate. No backend, no internet needed for the core loop.
- **9 reliably detectable targets**: bottle, cup, book, phone, backpack, bag, remote, keyboard, mouse. (Keys/wallet are honestly reported as unsupported — the model can't see them, so the app says so instead of faking it.)
- **Smooth tracking** — IoU-matched, exponentially-smoothed boxes so guidance doesn't jitter or drop on a missed frame.
- **Closed-loop voice guidance** — "Bottle, on your left. Move a little closer." Throttled TTS (no spam), urgent interrupt on found.
- **Proximity haptics** — vibration pulse rate rises as you close in; triple-pulse celebration on found.
- **Voice input** — tap the mic and say "find my phone".
- **Accessible UI** — large touch targets, high contrast, screen-reader labels, live regions; the camera preview is secondary, voice + haptics are primary.

## Tech

- Flutter (Android), CameraX via `camera` plugin
- `tflite_flutter` (LiteRT) — `assets/models/detect.tflite` + `labelmap.txt` bundled in the APK
- `flutter_tts`, `vibration`, `speech_to_text`, `permission_handler`
- Pure-Dart tracker + guidance engine, unit-tested

## Status

Working prototype (Phases 1–6). Detection pipeline verified by build + unit tests; **on-device camera testing is the next step** — model accuracy, sensor rotation, and overlay mapping are theoretically correct but not yet verified on hardware.

## Build

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## Honesty rules (we don't fake)

- No prerecorded video as "detection", no dummy boxes, no fake distances.
- Proximity comes from relative box size, not metric depth.
- Unsupported objects are reported as unsupported, never hallucinated.
- If something is technically impossible, we say so instead of faking it.
