import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide NotificationVisibility;
import 'package:flutter_tts/flutter_tts.dart';

// The callback function should always be a top-level function.
@pragma('vm:entry-point')
void startCallback() {
  // The setTaskHandler function must be called to handle the task in the background.
  FlutterForegroundTask.setTaskHandler(VoiceTaskHandler());
}

class VoiceTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('[VoiceTaskHandler] Foreground service started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Keep alive - no action needed
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('[VoiceTaskHandler] Foreground service stopped (timeout: $isTimeout)');
  }

  @override
  void onReceiveData(Object data) {
    print('[VoiceTaskHandler] Received data: $data');
  }

  @override
  void onNotificationButtonPressed(String id) {
    print('[VoiceTaskHandler] Notification button pressed: $id');
    // Bring app to foreground and trigger mic
    FlutterForegroundTask.launchApp('/');
    Future.delayed(const Duration(milliseconds: 100), () {
      FlutterForegroundTask.sendDataToMain('mic');
    });
  }

  @override
  void onNotificationPressed() {
    print('[VoiceTaskHandler] Notification tapped - launching app');
    // User tapped the notification body - bring app to foreground and start listening
    FlutterForegroundTask.launchApp('/');
    Future.delayed(const Duration(milliseconds: 100), () {
      FlutterForegroundTask.sendDataToMain('mic');
    });
  }

  @override
  void onNotificationDismissed() {
    print('[VoiceTaskHandler] Notification dismissed - restarting');
    // Restart the notification when user dismisses it
    FlutterForegroundTask.sendDataToMain('notification_dismissed');
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final FlutterTts _tts = FlutterTts();

  bool _isInitialized = false;
  bool _foregroundServiceRunning = false;

  // Notification IDs
  static const int _responseNotificationId = 2;
  static const String _channelId = 'neurix_voice';
  static const String _channelName = 'Neurix Voice';
  static const String _channelDescription = 'Voice interaction controls';

  // Callback for notification mic button press - triggers speech in HomeScreen
  VoidCallback? onMicPressed;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Android settings for local notifications (used for responses)
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationResponse,
    );

    // Initialize TTS
    await _initTts();

    // Initialize foreground task (Android only)
    if (Platform.isAndroid) {
      _initForegroundTask();
      // Initialize communication port and listen for data from foreground service
      FlutterForegroundTask.initCommunicationPort();
      FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    }

    _isInitialized = true;
    print('[NotificationService] Initialized');
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: _channelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false, // iOS doesn't support persistent notifications
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  void _onReceiveTaskData(Object data) {
    print('[NotificationService] Received from foreground service: $data');
    if (data == 'mic_pressed' || data == 'mic') {
      // Trigger HomeScreen's speech recognition via callback
      print('[NotificationService] Triggering mic callback');
      onMicPressed?.call();
    } else if (data == 'notification_dismissed') {
      // Restart the notification when user dismisses it
      _restartNotification();
    }
  }

  Future<void> _restartNotification() async {
    print('[NotificationService] Restarting notification after dismiss');
    // Update the service to show the notification again
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Neurix',
      notificationText: 'Tap to speak',
    );
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  void _onNotificationResponse(NotificationResponse response) {
    print('[NotificationService] Notification response - actionId: ${response.actionId}');
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
    print('[NotificationService] Background action: ${response.actionId}');
  }

  Future<void> _updateForegroundNotification({
    bool isListening = false,
    bool isProcessing = false,
  }) async {
    if (!Platform.isAndroid || !_foregroundServiceRunning) return;

    String title = 'Neurix';
    String body = 'Tap mic to speak';

    if (isListening) {
      title = 'Listening...';
      body = 'Speak now';
    } else if (isProcessing) {
      title = 'Processing...';
      body = 'Please wait';
    }

    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: body,
    );
  }

  /// Speak response
  Future<void> speakResponse(String response) async {
    // Show response in a separate notification
    await showResponseNotification(response);

    // Speak the response
    await _tts.speak(response);
  }

  /// Start the persistent foreground service with mic button
  Future<void> startForegroundService() async {
    if (!_isInitialized) await initialize();

    // Foreground service is Android-only
    if (!Platform.isAndroid) return;

    if (_foregroundServiceRunning) {
      print('[NotificationService] Foreground service already running');
      return;
    }

    // Request permission for notification (Android 13+)
    final notificationPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Start the foreground service
    // No action buttons - tapping the notification itself will open app and start listening
    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'Neurix',
      notificationText: 'Tap to speak',
      callback: startCallback,
    );

    _foregroundServiceRunning = result is ServiceRequestSuccess;
    print('[NotificationService] Foreground service started: $_foregroundServiceRunning');
  }

  /// Stop the foreground service
  Future<void> stopForegroundService() async {
    if (!Platform.isAndroid || !_foregroundServiceRunning) return;

    await FlutterForegroundTask.stopService();
    _foregroundServiceRunning = false;
    print('[NotificationService] Foreground service stopped');
  }

  /// Legacy method for compatibility - now starts foreground service
  Future<void> showVoiceNotification({
    String title = 'Neurix',
    String body = 'Tap mic to speak',
    bool isListening = false,
    bool isProcessing = false,
  }) async {
    if (!_isInitialized) await initialize();

    if (!Platform.isAndroid) return;

    if (!_foregroundServiceRunning) {
      await startForegroundService();
    } else {
      await _updateForegroundNotification(
        isListening: isListening,
        isProcessing: isProcessing,
      );
    }
  }

  /// Update notification to show listening state
  Future<void> showListeningNotification() async {
    await _updateForegroundNotification(isListening: true);
  }

  /// Update notification to show processing state
  Future<void> showProcessingNotification() async {
    await _updateForegroundNotification(isProcessing: true);
  }

  /// Show a response notification (separate from persistent notification)
  Future<void> showResponseNotification(String response) async {
    if (!_isInitialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      '${_channelId}_response',
      'Neurix Responses',
      channelDescription: 'Neurix response notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      color: Colors.green,
      colorized: true,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      _responseNotificationId,
      'Neurix Response',
      response,
      notificationDetails,
    );
  }

  /// Cancel the voice notification / stop foreground service
  Future<void> cancelVoiceNotification() async {
    await stopForegroundService();
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await stopForegroundService();
    await _notifications.cancelAll();
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      final permission = await FlutterForegroundTask.checkNotificationPermission();
      return permission == NotificationPermission.granted;
    }
    return true;
  }

  /// Request notification permission
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final permission = await FlutterForegroundTask.requestNotificationPermission();
      return permission == NotificationPermission.granted;
    } else if (Platform.isIOS) {
      final iosImpl = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosImpl != null) {
        final granted = await iosImpl.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
    }
    return true;
  }

  /// Dispose resources
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
  }
}
