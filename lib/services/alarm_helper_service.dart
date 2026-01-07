import 'dart:async';
import 'package:flutter/services.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:io' show Platform;

/// Helper service for alarm-related native functionality
class AlarmHelperService {
  static const MethodChannel _channel = MethodChannel('com.bunny.neuro/alarm');
  static const EventChannel _eventChannel = EventChannel('com.bunny.neuro/alarm_events');

  static StreamSubscription? _subscription;
  static Function()? _onCheckAlarm;

  /// Initialize the event listener for alarm events from native side
  static void initialize({Function()? onCheckAlarm}) {
    _onCheckAlarm = onCheckAlarm;
    _subscription?.cancel();
    _subscription = _eventChannel.receiveBroadcastStream().listen((event) {
      print('[AlarmHelperService] Received event: $event');
      if (event is Map && event['type'] == 'check_alarm') {
        print('[AlarmHelperService] Check alarm event received');
        _onCheckAlarm?.call();
      }
    }, onError: (error) {
      print('[AlarmHelperService] Event channel error: $error');
    });
  }

  /// Dispose the event listener
  static void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Wake up the screen (turns on display)
  static Future<bool> wakeUpScreen() async {
    try {
      final result = await _channel.invokeMethod('wakeUpScreen');
      return result == true;
    } catch (e) {
      print('[AlarmHelperService] Error waking up screen: $e');
      return false;
    }
  }

  /// Bring the app to foreground
  static Future<bool> bringToForeground() async {
    try {
      final result = await _channel.invokeMethod('bringToForeground');
      return result == true;
    } catch (e) {
      print('[AlarmHelperService] Error bringing to foreground: $e');
      return false;
    }
  }

  /// Send a broadcast to wake up the device and launch the app
  /// This can be called from a background isolate since it doesn't use method channels
  static Future<bool> sendWakeUpBroadcast() async {
    if (!Platform.isAndroid) return false;

    try {
      print('[AlarmHelperService] Sending wake up broadcast...');
      final intent = AndroidIntent(
        action: 'com.bunny.neuro.WAKE_UP_ALARM',
        package: 'com.bunny.neuro',
        componentName: 'com.bunny.neuro.AlarmReceiver',
      );
      await intent.sendBroadcast();
      print('[AlarmHelperService] Wake up broadcast sent');
      return true;
    } catch (e) {
      print('[AlarmHelperService] Error sending wake up broadcast: $e');
      return false;
    }
  }
}
