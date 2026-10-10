import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum VolumeKeyEventType {
  up,
  down,
  confirm,
}

class VolumeKeyEvent {
  const VolumeKeyEvent({required this.type, required this.detail});

  final VolumeKeyEventType type;
  final String detail;

  @override
  String toString() => 'VolumeKeyEvent(type: $type, detail: $detail)';
}

/// Service managing hardware volume button interception via native platform channel.
///
/// Ensures volume buttons only control language selection inside the language selection screen,
/// strictly restoring normal system volume controls everywhere else per PRD Section 6.
class VolumeKeyService {
  VolumeKeyService._();
  static final VolumeKeyService instance = VolumeKeyService._();

  static const MethodChannel _channel = MethodChannel('com.findit.findit/volume_keys');

  final StreamController<VolumeKeyEvent> _eventController =
      StreamController<VolumeKeyEvent>.broadcast();

  Stream<VolumeKeyEvent> get events => _eventController.stream;

  bool _isInterceptionActive = false;
  bool get isInterceptionActive => _isInterceptionActive;

  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onVolumeKeyEvent') {
      try {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final eventStr = args?['event'] as String? ?? '';
        final detailStr = args?['detail'] as String? ?? '';

        VolumeKeyEventType? eventType;
        if (eventStr == 'volume_up') {
          eventType = VolumeKeyEventType.up;
        } else if (eventStr == 'volume_down') {
          eventType = VolumeKeyEventType.down;
        } else if (eventStr == 'confirm') {
          eventType = VolumeKeyEventType.confirm;
        }

        if (eventType != null) {
          _eventController.add(VolumeKeyEvent(type: eventType, detail: detailStr));
        }
      } catch (e) {
        debugPrint('[VolumeKeyService] Error handling native call: $e');
      }
    }
  }

  /// Enables volume button interception in the native Android layer.
  /// Suppresses the system volume slider and audio stream adjustment.
  Future<bool> enableInterception() async {
    initialize();
    try {
      final res = await _channel.invokeMethod<bool>('enableVolumeInterception');
      _isInterceptionActive = res ?? false;
      return _isInterceptionActive;
    } catch (e) {
      debugPrint('[VolumeKeyService] Failed to enable interception: $e');
      _isInterceptionActive = false;
      return false;
    }
  }

  /// Disables volume button interception in the native Android layer.
  /// Completely restores standard system volume controls across Android.
  Future<bool> disableInterception() async {
    try {
      final res = await _channel.invokeMethod<bool>('disableVolumeInterception');
      _isInterceptionActive = !(res ?? true);
      return true;
    } catch (e) {
      debugPrint('[VolumeKeyService] Failed to disable interception: $e');
      _isInterceptionActive = false;
      return false;
    }
  }

  /// Manually dispatches an event (useful for on-screen gestures or keyboard testing fallback).
  void emitSyntheticEvent(VolumeKeyEventType type, {String detail = 'synthetic'}) {
    _eventController.add(VolumeKeyEvent(type: type, detail: detail));
  }
}
