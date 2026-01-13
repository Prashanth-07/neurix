import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechInitialized = false;
  bool _isListening = false;
  String _currentMode = '';
  String _transcribedText = '';
  Timer? _silenceTimer;
  DateTime? _lastSpeechTime;

  bool _isInitialized = false;

  // Notification IDs
  static const int _voiceNotificationId = 1;
  static const String _channelId = 'neurix_voice';
  static const String _channelName = 'Neurix Voice';
  static const String _channelDescription = 'Voice interaction controls';

  // Callback for notification actions - receives action and transcribed text
  Function(String action, String text)? onVoiceInput;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Android settings
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

    // Create notification channel for Android
    await _createNotificationChannel();

    // Initialize TTS
    await _initTts();

    // Initialize speech recognition
    await _initSpeech();

    _isInitialized = true;
    print('[NotificationService] Initialized');
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _initSpeech() async {
    _speechInitialized = await _speech.initialize(
      onStatus: (status) {
        print('[NotificationService] Speech status: $status');
        if (status == 'done' || status == 'notListening') {
          if (_isListening) {
            _silenceTimer?.cancel();
            if (_transcribedText.isNotEmpty) {
              _processVoiceInput();
            } else {
              _resetToIdle();
            }
          }
        }
      },
      onError: (error) {
        print('[NotificationService] Speech error: $error');
        _silenceTimer?.cancel();
        _resetToIdle();
      },
    );
    print('[NotificationService] Speech initialized: $_speechInitialized');
  }

  Future<void> _createNotificationChannel() async {
    // Only create notification channel on Android
    if (Platform.isAndroid) {
      const androidChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.low, // Low importance for persistent notification
        playSound: false,
        enableVibration: false,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    print('[NotificationService] Notification response - actionId: ${response.actionId}, notificationResponseType: ${response.notificationResponseType}');

    // If an action button was pressed
    if (response.actionId != null && response.actionId!.isNotEmpty) {
      _handleAction(response.actionId!);
    }
    // If notification body was tapped (no action id), start in speak mode
    else if (response.notificationResponseType == NotificationResponseType.selectedNotification) {
      _handleAction('speak');
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationResponse(NotificationResponse response) {
    print('[NotificationService] Background action: ${response.actionId}');
    // Background actions will be handled when app resumes
  }

  /// Handle notification action - start listening
  Future<void> _handleAction(String action) async {
    print('[NotificationService] Handling action: $action');

    if (_isListening) {
      print('[NotificationService] Already listening, ignoring action');
      return;
    }

    _currentMode = action;
    await _startListening();
  }

  Future<void> _startListening() async {
    if (!_speechInitialized) {
      await _initSpeech();
    }

    if (!_speechInitialized) {
      print('[NotificationService] Speech not available');
      await _tts.speak('Speech recognition is not available');
      return;
    }

    _isListening = true;
    _transcribedText = '';
    _lastSpeechTime = DateTime.now();

    // Update notification to show listening state
    await showVoiceNotification(isListening: true);

    // Start silence detection timer
    _startSilenceDetection();

    await _speech.listen(
      onResult: (result) {
        _transcribedText = result.recognizedWords;
        if (result.recognizedWords.isNotEmpty) {
          _lastSpeechTime = DateTime.now();
        }
        // Update notification with transcribed text
        _updateListeningNotification(_transcribedText);

        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _silenceTimer?.cancel();
          _speech.stop();
          _processVoiceInput();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: 'en_US',
    );
  }

  void _startSilenceDetection() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isListening) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final silenceDuration = now.difference(_lastSpeechTime ?? now);

      if (silenceDuration.inSeconds >= 5) {
        timer.cancel();
        _speech.stop();

        if (_transcribedText.isNotEmpty) {
          _processVoiceInput();
        } else {
          _resetToIdle();
        }
      }
    });
  }

  Future<void> _updateListeningNotification(String text) async {
    final displayText = text.isEmpty ? 'Listening...' : text;

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      color: Colors.red,
      colorized: true,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _voiceNotificationId,
      'Listening...',
      displayText,
      notificationDetails,
    );
  }

  Future<void> _processVoiceInput() async {
    _isListening = false;

    // Show processing notification
    await showVoiceNotification(isProcessing: true);

    print('[NotificationService] Processing: $_currentMode - $_transcribedText');

    // Call the callback to process the voice input
    if (onVoiceInput != null && _transcribedText.isNotEmpty) {
      onVoiceInput!(_currentMode, _transcribedText);
    } else {
      await _resetToIdle();
    }
  }

  Future<void> _resetToIdle() async {
    _isListening = false;
    _transcribedText = '';
    _currentMode = '';
    _silenceTimer?.cancel();
    await showVoiceNotification();
  }

  /// Speak response and reset to idle
  Future<void> speakResponse(String response) async {
    // Show response in notification
    await showResponseNotification(response);

    // Speak the response
    await _tts.speak(response);

    // Wait a bit then reset to idle
    await Future.delayed(const Duration(seconds: 2));
    await showVoiceNotification();
  }

  /// Show the voice control notification
  Future<void> showVoiceNotification({
    String title = 'Neurix Voice',
    String body = 'Tap to speak or use actions below',
    bool isListening = false,
    bool isProcessing = false,
  }) async {
    if (!_isInitialized) await initialize();

    // Persistent notification is Android-only feature
    // iOS doesn't support persistent notifications in the same way
    if (!Platform.isAndroid) {
      return;
    }

    String currentTitle = title;
    String currentBody = body;

    if (isListening) {
      currentTitle = 'Listening...';
      currentBody = 'Speak now to add a memory or search';
    } else if (isProcessing) {
      currentTitle = 'Processing...';
      currentBody = 'Please wait';
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true, // Makes it persistent
      autoCancel: false,
      showWhen: false,
      color: Colors.deepPurple,
      colorized: true,
      actions: isListening || isProcessing
          ? null // No actions while listening/processing
          : [
              const AndroidNotificationAction(
                'speak',
                '🎤 Speak',
                showsUserInterface: true, // Need app foreground for microphone
                cancelNotification: false,
              ),
              const AndroidNotificationAction(
                'add_memory',
                '💾 Add Memory',
                showsUserInterface: true,
                cancelNotification: false,
              ),
              const AndroidNotificationAction(
                'search',
                '🔍 Search',
                showsUserInterface: true,
                cancelNotification: false,
              ),
            ],
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      _voiceNotificationId,
      currentTitle,
      currentBody,
      notificationDetails,
    );
  }

  /// Update notification to show listening state
  Future<void> showListeningNotification() async {
    await showVoiceNotification(isListening: true);
  }

  /// Update notification to show processing state
  Future<void> showProcessingNotification() async {
    await showVoiceNotification(isProcessing: true);
  }

  /// Update notification to show response
  Future<void> showResponseNotification(String response) async {
    if (!_isInitialized) await initialize();

    // Response notifications work on both platforms
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
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
      _voiceNotificationId + 1, // Different ID for response
      'Neurix Response',
      response,
      notificationDetails,
    );

    // Also show the main control notification again (Android only)
    if (Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 500));
      await showVoiceNotification();
    }
  }

  /// Cancel the voice notification
  Future<void> cancelVoiceNotification() async {
    await _notifications.cancel(_voiceNotificationId);
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      final androidImpl = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        return await androidImpl.areNotificationsEnabled() ?? false;
      }
    }
    // iOS permissions are handled during initialization
    return true;
  }

  /// Request notification permission
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final androidImpl = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final granted = await androidImpl.requestNotificationsPermission();
        return granted ?? false;
      }
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
}
