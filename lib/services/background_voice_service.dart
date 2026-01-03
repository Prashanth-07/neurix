import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

class BackgroundVoiceService {
  static final BackgroundVoiceService _instance = BackgroundVoiceService._internal();
  factory BackgroundVoiceService() => _instance;
  BackgroundVoiceService._internal();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  bool _isInitialized = false;

  // Callback for when voice input is received
  Function(String action, String text)? onVoiceInput;

  // Stream controller for communication between service and main app
  static final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  static Stream<Map<String, dynamic>> get events => _eventController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Create the notification channel BEFORE configuring the service
    final FlutterLocalNotificationsPlugin notifications =
        FlutterLocalNotificationsPlugin();

    const androidChannel = AndroidNotificationChannel(
      'neurix_voice_bg',
      'Neurix Voice Background',
      description: 'Voice recording in background',
      importance: Importance.low,
    );

    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    print('[BackgroundVoiceService] Notification channel created');

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'neurix_voice_bg',
        initialNotificationTitle: 'Neurix Voice',
        initialNotificationContent: 'Ready for voice commands',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.microphone],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    // Listen for events from the background service
    _service.on('voiceResult').listen((event) {
      if (event != null && onVoiceInput != null) {
        final action = event['action'] as String?;
        final text = event['text'] as String?;
        if (action != null && text != null && text.isNotEmpty) {
          onVoiceInput!(action, text);
        }
      }
    });

    _service.on('listeningState').listen((event) {
      if (event != null) {
        _eventController.add(event);
      }
    });

    _isInitialized = true;
    print('[BackgroundVoiceService] Initialized');
  }

  /// Start the background service and begin listening
  Future<void> startListening(String action) async {
    if (!_isInitialized) await initialize();

    final isRunning = await _service.isRunning();
    if (!isRunning) {
      await _service.startService();
      // Wait a bit for service to start
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Send command to start listening with the action type
    _service.invoke('startListening', {'action': action});
  }

  /// Stop listening
  Future<void> stopListening() async {
    _service.invoke('stopListening');
  }

  /// Stop the background service
  Future<void> stopService() async {
    _service.invoke('stopService');
  }

  /// Check if service is running
  Future<bool> isRunning() async {
    return await _service.isRunning();
  }
}

// This runs in the background isolate
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final stt.SpeechToText speech = stt.SpeechToText();
  final FlutterTts tts = FlutterTts();
  bool speechInitialized = false;
  bool isListening = false;
  String currentAction = '';
  String transcribedText = '';
  Timer? silenceTimer;
  DateTime? lastSpeechTime;

  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  // Initialize notifications
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await notifications.initialize(initSettings);

  // Initialize speech
  Future<void> initSpeech() async {
    speechInitialized = await speech.initialize(
      onStatus: (status) {
        print('[BGService] Speech status: $status');
        if (status == 'done' || status == 'notListening') {
          if (isListening) {
            silenceTimer?.cancel();
            if (transcribedText.isNotEmpty) {
              // Send result back to main app
              service.invoke('voiceResult', {
                'action': currentAction,
                'text': transcribedText,
              });
            }
            isListening = false;
            // Update notification back to idle
            _updateNotification(notifications, 'Neurix Voice', 'Ready for voice commands');
          }
        }
      },
      onError: (error) {
        print('[BGService] Speech error: $error');
        silenceTimer?.cancel();
        isListening = false;
        _updateNotification(notifications, 'Neurix Voice', 'Ready for voice commands');
      },
    );
    print('[BGService] Speech initialized: $speechInitialized');
  }

  // Initialize TTS
  await tts.setLanguage('en-US');
  await tts.setSpeechRate(0.5);
  await tts.setVolume(1.0);

  // Handle start listening command
  service.on('startListening').listen((event) async {
    if (isListening) {
      print('[BGService] Already listening, ignoring');
      return;
    }

    currentAction = event?['action'] ?? 'speak';
    transcribedText = '';
    lastSpeechTime = DateTime.now();

    if (!speechInitialized) {
      await initSpeech();
    }

    if (!speechInitialized) {
      print('[BGService] Speech not available');
      await tts.speak('Speech recognition is not available');
      return;
    }

    isListening = true;
    service.invoke('listeningState', {'isListening': true, 'action': currentAction});

    // Update notification to show listening
    _updateNotification(notifications, 'Listening...', 'Speak now');

    // Start silence detection
    silenceTimer?.cancel();
    silenceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isListening) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final silenceDuration = now.difference(lastSpeechTime ?? now);

      if (silenceDuration.inSeconds >= 5) {
        timer.cancel();
        speech.stop();
        if (transcribedText.isNotEmpty) {
          service.invoke('voiceResult', {
            'action': currentAction,
            'text': transcribedText,
          });
        }
        isListening = false;
        _updateNotification(notifications, 'Neurix Voice', 'Ready for voice commands');
      }
    });

    await speech.listen(
      onResult: (result) {
        transcribedText = result.recognizedWords;
        if (result.recognizedWords.isNotEmpty) {
          lastSpeechTime = DateTime.now();
        }
        // Update notification with transcribed text
        _updateNotification(
          notifications,
          'Listening...',
          transcribedText.isEmpty ? 'Speak now' : transcribedText,
        );

        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          silenceTimer?.cancel();
          speech.stop();
          service.invoke('voiceResult', {
            'action': currentAction,
            'text': transcribedText,
          });
          isListening = false;
          _updateNotification(notifications, 'Neurix Voice', 'Ready for voice commands');
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: 'en_US',
    );
  });

  // Handle stop listening command
  service.on('stopListening').listen((event) async {
    if (isListening) {
      silenceTimer?.cancel();
      await speech.stop();
      isListening = false;
      service.invoke('listeningState', {'isListening': false});
      _updateNotification(notifications, 'Neurix Voice', 'Ready for voice commands');
    }
  });

  // Handle stop service command
  service.on('stopService').listen((event) async {
    silenceTimer?.cancel();
    await speech.stop();
    await service.stopSelf();
  });

  // Keep service running
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }
}

Future<void> _updateNotification(
  FlutterLocalNotificationsPlugin notifications,
  String title,
  String body,
) async {
  const androidDetails = AndroidNotificationDetails(
    'neurix_voice_bg',
    'Neurix Voice Background',
    channelDescription: 'Voice recording in background',
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    autoCancel: false,
    showWhen: false,
  );

  const notificationDetails = NotificationDetails(android: androidDetails);

  await notifications.show(
    888,
    title,
    body,
    notificationDetails,
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}
