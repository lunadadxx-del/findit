import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service managing Android Compliant Foreground Microphone Service for Lost Phone Mode.
///
/// Features:
/// - Microphone is strictly kept OFF during normal app use.
/// - Only when Lost Phone Mode is enabled, requests RECORD_AUDIO and POST_NOTIFICATIONS
///   and starts a compliant Android foreground service with microphone type.
/// - Continuous hotword listener watches for "Hey Iris" (or "Find my phone").
/// - When detected, triggers max-volume alarm and SOS vibration.
/// - Automatically shuts off after [timeoutMinutes] (default 20 min) or on battery low
///   to prevent draining phone battery.
class LostPhoneService extends ChangeNotifier {
  LostPhoneService._();
  static final LostPhoneService instance = LostPhoneService._();

  static const MethodChannel _channel = MethodChannel('com.findit.findit/lost_phone');

  bool _initialized = false;
  bool _isRunning = false;
  bool _isAlarmRinging = false;
  String? _triggeredPhrase;
  String? _lastError;
  String? _lastVoiceCommand;
  DateTime? _lastVoiceCommandTime;

  bool get isRunning => _isRunning;
  bool get isAlarmRinging => _isAlarmRinging;
  String? get triggeredPhrase => _triggeredPhrase;
  String? get lastError => _lastError;

  final StreamController<bool> _runningController = StreamController<bool>.broadcast();
  final StreamController<bool> _alarmController = StreamController<bool>.broadcast();
  final StreamController<void> _alarmStoppedController = StreamController<void>.broadcast();
  final StreamController<String> _triggerController = StreamController<String>.broadcast();
  final StreamController<String> _irisWakeupController = StreamController<String>.broadcast();
  final StreamController<String> _voiceCommandController = StreamController<String>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();

  Stream<bool> get onRunningChanged => _runningController.stream;
  Stream<bool> get onAlarmChanged => _alarmController.stream;
  Stream<void> get onAlarmStopped => _alarmStoppedController.stream;
  Stream<String> get onTriggerDetected => _triggerController.stream;
  Stream<String> get onIrisWakeup => _irisWakeupController.stream;
  Stream<String> get onVoiceCommand => _voiceCommandController.stream;
  Stream<String> get onErrorOccurred => _errorController.stream;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCallback);
    refreshState();
  }

  Future<void> refreshState() async {
    try {
      final running = await _channel.invokeMethod<bool>('isServiceRunning') ?? false;
      final alarm = await _channel.invokeMethod<bool>('isAlarmRinging') ?? false;
      _isRunning = running;
      _isAlarmRinging = alarm;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _handleNativeCallback(MethodCall call) async {
    switch (call.method) {
      case 'onServiceStateChanged':
        final args = call.arguments as Map<dynamic, dynamic>?;
        final running = args?['isRunning'] as bool? ?? false;
        _isRunning = running;
        if (!running) {
          _isAlarmRinging = false;
        }
        _runningController.add(running);
        notifyListeners();
        break;

      case 'onAlarmTriggered':
        final args = call.arguments as Map<dynamic, dynamic>?;
        final phrase = args?['phrase'] as String? ?? 'Hey Iris';
        _isAlarmRinging = true;
        _triggeredPhrase = phrase;
        _alarmController.add(true);
        _triggerController.add(phrase);
        notifyListeners();
        break;

      case 'onAlarmStopped':
        _isAlarmRinging = false;
        _alarmController.add(false);
        _alarmStoppedController.add(null);
        notifyListeners();
        break;

      case 'onIrisWakeup':
        final args = call.arguments as Map<dynamic, dynamic>?;
        final phrase = args?['phrase'] as String? ?? 'Hey Iris';
        _irisWakeupController.add(phrase);
        notifyListeners();
        break;

      case 'onVoiceCommand':
        final args = call.arguments as Map<dynamic, dynamic>?;
        final command = args?['command'] as String? ?? '';
        final now = DateTime.now();
        if (command.isNotEmpty) {
          if (_lastVoiceCommand == command &&
              _lastVoiceCommandTime != null &&
              now.difference(_lastVoiceCommandTime!) < const Duration(milliseconds: 1500)) {
            break;
          }
          _lastVoiceCommand = command;
          _lastVoiceCommandTime = now;
          _voiceCommandController.add(command);
          notifyListeners();
        }
        break;

      case 'onServiceError':
        final args = call.arguments as Map<dynamic, dynamic>?;
        final error = args?['error'] as String? ?? 'Unknown error';
        _lastError = error;
        _errorController.add(error);
        notifyListeners();
        break;
    }
  }

  /// Checks and requests necessary permissions (Microphone + Notifications).
  /// Returns a status result with diagnostic information.
  Future<({bool success, String? message})> checkAndRequestPermissions() async {
    // 1. Microphone permission
    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        return (
          success: false,
          message: 'Microphone permission is required to listen for "Hey Iris".',
        );
      }
    }

    // 2. Notification permission (Android 13+ / API 33+)
    var notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      notifStatus = await Permission.notification.request();
      if (!notifStatus.isGranted) {
        return (
          success: false,
          message:
              'Notification permission is required to keep Lost Phone Mode active in the background.',
        );
      }
    }

    return (success: true, message: null);
  }

  /// Starts compliant foreground microphone service with [timeoutMinutes] auto-shutoff.
  Future<bool> startLostPhoneMode({int timeoutMinutes = 20}) async {
    initialize();
    _lastError = null;

    final permCheck = await checkAndRequestPermissions();
    if (!permCheck.success) {
      _lastError = permCheck.message;
      notifyListeners();
      return false;
    }

    try {
      final success = await _channel.invokeMethod<bool>(
            'startLostPhoneMode',
            {'timeoutMinutes': timeoutMinutes},
          ) ??
          false;
      if (success) {
        _isRunning = true;
        _isAlarmRinging = false;
        notifyListeners();
      }
      return success;
    } on PlatformException catch (e) {
      _lastError = e.message ?? 'Failed to start Lost Phone Mode.';
      notifyListeners();
      return false;
    }
  }

  /// Stops Lost Phone Mode foreground service completely.
  Future<bool> stopLostPhoneMode() async {
    initialize();
    try {
      final success =
          await _channel.invokeMethod<bool>('stopLostPhoneMode') ?? false;
      _isRunning = false;
      _isAlarmRinging = false;
      notifyListeners();
      return success;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Silences an actively ringing alarm without stopping the service.
  Future<bool> stopAlarm() async {
    initialize();
    try {
      final success = await _channel.invokeMethod<bool>('stopAlarm') ?? false;
      _isAlarmRinging = false;
      notifyListeners();
      return success;
    } catch (e) {
      return false;
    }
  }

  /// Sounds a loud test alert and vibration to verify loudness before leaving phone.
  Future<bool> testAlarm() async {
    initialize();
    try {
      return await _channel.invokeMethod<bool>('testAlarm') ?? false;
    } catch (_) {
      return false;
    }
  }
}
