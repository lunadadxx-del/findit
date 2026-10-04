import 'package:flutter_tts/flutter_tts.dart';

/// Throttled text-to-speech.
///
/// Blind users need guidance, not a chatterbox. This wrapper:
/// - never repeats the same phrase back-to-back,
/// - enforces a minimum gap between utterances,
/// - always lets a "found" announcement interrupt.
///
/// Call [speak] freely; it decides whether the user should hear it.
class SpeechService {
  SpeechService({this.minGap = const Duration(seconds: 3)});

  final Duration minGap;
  final FlutterTts _tts = FlutterTts();

  bool _ready = false;
  String _lastPhrase = '';
  DateTime _lastSpokeAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> initialize() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.95);
      await _tts.setPitch(1.0);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Speak [phrase] if it is worth saying out loud.
  /// Set [urgent] for the "found" announcement — it always speaks.
  Future<void> speak(String phrase, {bool urgent = false}) async {
    if (!_ready || phrase.isEmpty) return;
    final now = DateTime.now();
    if (!urgent) {
      if (phrase == _lastPhrase) return;
      if (now.difference(_lastSpokeAt) < minGap) return;
    } else {
      await _tts.stop();
    }
    _lastPhrase = phrase;
    _lastSpokeAt = now;
    try {
      await _tts.speak(phrase);
    } catch (_) {
      // Speech must never crash the guidance loop.
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _lastPhrase = '';
  }

  Future<void> dispose() async {
    await stop();
  }
}
