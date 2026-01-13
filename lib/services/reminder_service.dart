import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/reminder_model.dart';
import 'local_db_service.dart';

// Conditional imports for Android-specific packages
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart'
    if (dart.library.html) 'alarm_stub.dart';
import 'alarm_helper_service.dart'
    if (dart.library.html) 'alarm_stub.dart';

/// Top-level callback for AndroidAlarmManager - runs in isolate when alarm fires
/// This enables TTS to speak when the notification triggers and launches the alarm screen
@pragma('vm:entry-point')
Future<void> alarmCallback(int alarmId) async {
  print('[AlarmCallback] ===== ALARM FIRED =====');
  print('[AlarmCallback] Alarm ID: $alarmId');

  try {
    // Ensure Flutter bindings are initialized for background isolate
    DartPluginRegistrant.ensureInitialized();

    // Get reminder data from SharedPreferences
    // IMPORTANT: Reload SharedPreferences to get fresh data from disk
    // The background isolate may have a stale cached instance
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force reload from disk to get latest data
    print('[AlarmCallback] SharedPreferences reloaded');

    final reminderJson = prefs.getString('alarm_$alarmId');
    print('[AlarmCallback] Looking for key: alarm_$alarmId, found: ${reminderJson != null}');

    if (reminderJson == null) {
      // This is likely a stale alarm from a previous session - cancel it silently
      print('[AlarmCallback] No reminder data found for alarm $alarmId (stale alarm, ignoring)');
      // Try to cancel this stale alarm to prevent future triggers
      try {
        await AndroidAlarmManager.cancel(alarmId);
        print('[AlarmCallback] Cancelled stale alarm $alarmId');
      } catch (e) {
        print('[AlarmCallback] Could not cancel stale alarm: $e');
      }
      return;
    }

    final reminderData = jsonDecode(reminderJson) as Map<String, dynamic>;
    final message = reminderData['message'] as String? ?? 'Reminder';
    final reminderId = reminderData['id'] as String? ?? '';
    final isRecurring = reminderData['isRecurring'] as bool? ?? false;
    final intervalMinutes = reminderData['intervalMinutes'] as int?;
    final scheduledTimeMs = reminderData['scheduledTimeMs'] as int?;

    print('[AlarmCallback] Message: "$message"');
    print('[AlarmCallback] Is Recurring: $isRecurring');

    // For one-time alarms, check if the scheduled time has passed by more than 10 minutes
    // This prevents stale alarms from firing when the app restarts
    if (!isRecurring && scheduledTimeMs != null) {
      final scheduledTime = DateTime.fromMillisecondsSinceEpoch(scheduledTimeMs);
      final now = DateTime.now();
      final difference = now.difference(scheduledTime);

      if (difference.inMinutes > 10) {
        print('[AlarmCallback] One-time alarm is too old (${difference.inMinutes}min past scheduled time), ignoring');
        // Clean up ALL data for this stale alarm
        await prefs.remove('alarm_$alarmId');
        await AndroidAlarmManager.cancel(alarmId);
        // Also clean up any active alarm data that might be related
        final activeAlarmId = prefs.getInt('active_alarm_id');
        if (activeAlarmId == alarmId) {
          await prefs.remove('active_alarm_id');
          await prefs.remove('active_alarm_message');
          await prefs.remove('active_alarm_timestamp');
          print('[AlarmCallback] Cleaned up stale active alarm data');
        }
        return;
      }
    }

    // Store active alarm data for the app to pick up when it opens
    // Include timestamp so we can expire old alarms
    await prefs.setInt('active_alarm_id', alarmId);
    await prefs.setString('active_alarm_message', message);
    await prefs.setInt('active_alarm_timestamp', DateTime.now().millisecondsSinceEpoch);
    await prefs.setString('active_alarm_reminder_id', reminderId);
    print('[AlarmCallback] Stored active alarm for app launch (with timestamp, reminderId: $reminderId)');

    // Send wake-up broadcast to ensure device wakes up and app comes to foreground
    // This is especially important for recurring alarms when the app is already in background
    try {
      await AlarmHelperService.sendWakeUpBroadcast();
      print('[AlarmCallback] Wake-up broadcast sent');
    } catch (e) {
      print('[AlarmCallback] Wake-up broadcast failed (non-fatal): $e');
    }

    // Initialize and show notification with full-screen intent to launch the app
    final notifications = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await notifications.initialize(initSettings);

    // Use a unique notification ID for each alarm trigger (especially for recurring)
    // This forces Android to treat it as a new notification and properly trigger fullScreenIntent
    final notificationId = DateTime.now().millisecondsSinceEpoch % 100000;

    // Cancel any previous alarm notifications to ensure clean state
    // This helps Android properly trigger the fullScreenIntent for the new notification
    final previousNotificationId = 1000 + alarmId % 10000;
    await notifications.cancel(previousNotificationId);
    print('[AlarmCallback] Cancelled previous notification: $previousNotificationId');

    final androidDetails = AndroidNotificationDetails(
      'neurix_alarms',
      'Neurix Alarms',
      channelDescription: 'Alarm notifications with full screen',
      importance: Importance.max,
      priority: Priority.max,
      autoCancel: false,
      fullScreenIntent: true,
      ongoing: true,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      actions: isRecurring
          ? [
              const AndroidNotificationAction('snooze', 'Snooze 10min', cancelNotification: true),
              const AndroidNotificationAction('stop', 'Stop Reminder', cancelNotification: true),
            ]
          : [
              const AndroidNotificationAction('snooze', 'Snooze 10min', cancelNotification: true),
              const AndroidNotificationAction('dismiss', 'Dismiss', cancelNotification: true),
            ],
    );

    await notifications.show(
      notificationId,
      'Reminder: $message',
      message,
      NotificationDetails(android: androidDetails),
      payload: '$alarmId|$message',
    );
    print('[AlarmCallback] Notification shown with fullScreenIntent');

    // Speak the reminder using TTS
    try {
      print('[AlarmCallback] Initializing TTS...');
      final tts = FlutterTts();
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.5);
      await tts.setVolume(1.0);
      await tts.awaitSpeakCompletion(true);
      print('[AlarmCallback] Speaking reminder...');
      await tts.speak('Reminder: $message');
      print('[AlarmCallback] TTS completed');
    } catch (ttsError) {
      print('[AlarmCallback] TTS error (non-fatal): $ttsError');
    }

    // For recurring reminders, schedule the next alarm
    // BUT FIRST: Reload prefs and verify the alarm data still exists
    // This prevents rescheduling deleted reminders
    if (isRecurring && intervalMinutes != null && intervalMinutes > 0) {
      // Reload SharedPreferences to get the latest state (user may have deleted)
      await prefs.reload();
      final stillExists = prefs.getString('alarm_$alarmId');

      if (stillExists == null) {
        print('[AlarmCallback] Alarm data was deleted, NOT rescheduling recurring alarm');
        // Clean up any remaining active alarm data
        await prefs.remove('active_alarm_id');
        await prefs.remove('active_alarm_message');
        await prefs.remove('active_alarm_timestamp');
        await prefs.remove('active_alarm_reminder_id');
      } else {
        final nextAlarmTime = DateTime.now().add(Duration(minutes: intervalMinutes));
        print('[AlarmCallback] Scheduling next recurring alarm for: $nextAlarmTime');

        // Update the stored reminder data with the new scheduled time
        final updatedReminderData = jsonEncode({
          'id': reminderId,
          'message': message,
          'isRecurring': true,
          'intervalMinutes': intervalMinutes,
          'scheduledTimeMs': nextAlarmTime.millisecondsSinceEpoch,
        });
        await prefs.setString('alarm_$alarmId', updatedReminderData);
        print('[AlarmCallback] Updated alarm data for next occurrence');

        await AndroidAlarmManager.oneShotAt(
          nextAlarmTime,
          alarmId,
          alarmCallback,
          exact: true,
          wakeup: true,
          rescheduleOnReboot: true,
          allowWhileIdle: true,
        );
      }
    }
    // Note: We don't clean up alarm data here anymore - it's cleaned up when user dismisses the alarm screen

    print('[AlarmCallback] ===== ALARM COMPLETE =====');
  } catch (e, stack) {
    print('[AlarmCallback] Error: $e');
    print('[AlarmCallback] Stack: $stack');
  }
}

class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  final LocalDbService _dbService = LocalDbService();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final FlutterTts _tts = FlutterTts();

  Timer? _checkTimer;
  bool _isInitialized = false;

  // Notification channel for reminders
  static const String _channelId = 'neurix_reminders';
  static const String _channelName = 'Neurix Reminders';
  static const String _channelDescription = 'Reminder notifications';

  // Base notification ID for reminders (use reminder hashcode for unique IDs)
  static const int _baseNotificationId = 1000;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize timezone data and set local timezone
    tz_data.initializeTimeZones();

    // Set the local timezone based on device's timezone offset
    // This is critical for scheduled notifications to work correctly
    final now = DateTime.now();
    final offsetHours = now.timeZoneOffset.inHours;
    final offsetMinutes = now.timeZoneOffset.inMinutes % 60;

    // Find a matching timezone or use a generic one
    String timezoneName = _getTimezoneNameFromOffset(now.timeZoneOffset);
    try {
      tz.setLocalLocation(tz.getLocation(timezoneName));
      print('[ReminderService] Timezone set to: $timezoneName (UTC${offsetHours >= 0 ? '+' : ''}$offsetHours:${offsetMinutes.toString().padLeft(2, '0')})');
    } catch (e) {
      // Fallback: use UTC and adjust manually
      print('[ReminderService] Could not set timezone $timezoneName, using UTC with offset');
      tz.setLocalLocation(tz.UTC);
    }

    // Initialize TTS
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);

    // Initialize Android Alarm Manager for background scheduling (Android only)
    if (Platform.isAndroid) {
      await AndroidAlarmManager.initialize();
    }

    // Initialize notifications with callback for handling actions
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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
    );

    // Create notification channel (Android only)
    if (Platform.isAndroid) {
      const androidChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.createNotificationChannel(androidChannel);

      // Request exact alarm permission (required for Android 12+)
      await _requestExactAlarmPermission(androidPlugin);

      // Clean up any orphaned alarm data from previous sessions
      await _cleanupOrphanedAlarmData();
    }

    // iOS: Request notification permissions
    if (Platform.isIOS) {
      final iosPlugin = _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    // Reschedule any active reminders on app start
    await _rescheduleAllActiveReminders();

    _isInitialized = true;
    print('[ReminderService] Initialized${Platform.isAndroid ? ' with AlarmManager' : ' for iOS'}');
  }

  /// Request exact alarm permission for Android 12+ (API 31+)
  Future<void> _requestExactAlarmPermission(AndroidFlutterLocalNotificationsPlugin? androidPlugin) async {
    if (androidPlugin == null) return;

    // Check if exact alarms are permitted
    final exactAlarmPermissionStatus = await androidPlugin.canScheduleExactNotifications();
    print('[ReminderService] Exact alarm permission status: $exactAlarmPermissionStatus');

    if (exactAlarmPermissionStatus != true) {
      print('[ReminderService] Requesting exact alarm permission...');
      // Request the permission - this opens system settings on Android 12+
      final granted = await androidPlugin.requestExactAlarmsPermission();
      print('[ReminderService] Exact alarm permission granted: $granted');
    }

    // Also request notification permission for Android 13+
    final notificationStatus = await Permission.notification.status;
    print('[ReminderService] Notification permission status: $notificationStatus');

    if (!notificationStatus.isGranted) {
      print('[ReminderService] Requesting notification permission...');
      final result = await Permission.notification.request();
      print('[ReminderService] Notification permission result: $result');
    }
  }

  /// Handle notification response
  void _onNotificationResponse(NotificationResponse response) {
    print('[ReminderService] Notification response: ${response.actionId}');
    if (response.actionId != null && response.payload != null) {
      handleNotificationAction(response.actionId!, response.payload);
    }
  }

  /// Clean up ALL alarm-related data for a specific alarm ID
  /// This ensures no stale data remains in SharedPreferences
  Future<void> _cleanupAlarmData(int alarmId, {bool cancelAlarm = true}) async {
    print('[ReminderService] Cleaning up all data for alarm $alarmId');

    // Android-specific cleanup
    if (Platform.isAndroid) {
      final prefs = await SharedPreferences.getInstance();

      // Remove alarm-specific data
      await prefs.remove('alarm_$alarmId');

      // Remove active alarm data if it matches this alarm
      final activeAlarmId = prefs.getInt('active_alarm_id');
      if (activeAlarmId == alarmId) {
        await prefs.remove('active_alarm_id');
        await prefs.remove('active_alarm_message');
        await prefs.remove('active_alarm_timestamp');
        print('[ReminderService] Removed active alarm data for $alarmId');
      }

      // Cancel the Android alarm
      if (cancelAlarm) {
        await AndroidAlarmManager.cancel(alarmId);
        print('[ReminderService] Cancelled Android alarm $alarmId');
      }
    }

    // Cancel any related notification (works on both platforms)
    final notificationId = _baseNotificationId + alarmId % 10000;
    await _notifications.cancel(notificationId);
    print('[ReminderService] Cancelled notification $notificationId');
  }

  /// Clean up orphaned alarm data from previous sessions
  /// This runs on app startup to ensure no stale data causes issues
  Future<void> _cleanupOrphanedAlarmData() async {
    try {
      print('[ReminderService] Checking for orphaned alarm data...');
      final prefs = await SharedPreferences.getInstance();

      // Get all keys that start with 'alarm_'
      final allKeys = prefs.getKeys();
      final alarmKeys = allKeys.where((key) => key.startsWith('alarm_')).toList();

      print('[ReminderService] Found ${alarmKeys.length} alarm data entries');

      // Get all active reminders to compare
      final activeReminders = await _dbService.getAllActiveReminders();
      final activeAlarmIds = activeReminders
          .map((r) => r.id.hashCode.abs() % 100000)
          .toSet();

      final now = DateTime.now();

      for (final key in alarmKeys) {
        try {
          final alarmIdStr = key.replaceFirst('alarm_', '');
          final alarmId = int.tryParse(alarmIdStr);
          if (alarmId == null) continue;

          final dataJson = prefs.getString(key);
          if (dataJson == null) {
            // Empty data - clean up
            await prefs.remove(key);
            await AndroidAlarmManager.cancel(alarmId);
            print('[ReminderService] Removed empty alarm data: $key');
            continue;
          }

          final data = jsonDecode(dataJson) as Map<String, dynamic>;
          final isRecurring = data['isRecurring'] as bool? ?? false;
          final scheduledTimeMs = data['scheduledTimeMs'] as int?;

          // For one-time alarms, check if they're expired
          if (!isRecurring && scheduledTimeMs != null) {
            final scheduledTime = DateTime.fromMillisecondsSinceEpoch(scheduledTimeMs);
            final difference = now.difference(scheduledTime);

            // If more than 10 minutes past scheduled time, clean up
            if (difference.inMinutes > 10) {
              print('[ReminderService] Found expired alarm data: $key (${difference.inMinutes}min past)');
              await _cleanupAlarmData(alarmId);
              continue;
            }
          }

          // Check if there's no corresponding active reminder
          if (!activeAlarmIds.contains(alarmId)) {
            print('[ReminderService] Found orphaned alarm data: $key (no active reminder)');
            await _cleanupAlarmData(alarmId);
          }
        } catch (e) {
          print('[ReminderService] Error processing alarm key $key: $e');
        }
      }

      // Also clean up stale active_alarm_* data
      final activeAlarmId = prefs.getInt('active_alarm_id');
      final activeAlarmTimestamp = prefs.getInt('active_alarm_timestamp');

      if (activeAlarmId != null && activeAlarmTimestamp != null) {
        final alarmTime = DateTime.fromMillisecondsSinceEpoch(activeAlarmTimestamp);
        final difference = now.difference(alarmTime);

        // If active alarm data is more than 5 minutes old, clean it up
        if (difference.inMinutes > 5) {
          print('[ReminderService] Cleaning up stale active alarm data (${difference.inMinutes}min old)');
          await prefs.remove('active_alarm_id');
          await prefs.remove('active_alarm_message');
          await prefs.remove('active_alarm_timestamp');
        }
      }

      print('[ReminderService] Orphaned alarm data cleanup complete');
    } catch (e) {
      print('[ReminderService] Error cleaning up orphaned alarm data: $e');
    }
  }

  /// Reschedule all active reminders (called on app start)
  /// For one-time reminders that have already passed, mark them as inactive
  /// For recurring reminders, reschedule the next occurrence
  Future<void> _rescheduleAllActiveReminders() async {
    try {
      final reminders = await _dbService.getAllActiveReminders();
      print('[ReminderService] Rescheduling ${reminders.length} active reminders');

      final now = DateTime.now();
      for (final reminder in reminders) {
        // Check if the reminder time has already passed
        if (reminder.nextTrigger != null && reminder.nextTrigger!.isBefore(now)) {
          if (reminder.type == ReminderType.oneTime) {
            // One-time reminder that has passed - mark as inactive AND clean up ALL alarm data
            print('[ReminderService] One-time reminder "${reminder.message}" has passed, marking inactive');
            final inactiveReminder = reminder.copyWith(isActive: false);
            await _dbService.updateReminder(inactiveReminder);

            // Clean up ALL alarm-related data for this reminder
            final alarmId = reminder.id.hashCode.abs() % 100000;
            await _cleanupAlarmData(alarmId);

            print('[ReminderService] Fully cleaned up expired reminder "${reminder.message}" (alarm $alarmId)');
            continue;
          } else if (reminder.type == ReminderType.recurring) {
            // Recurring reminder - calculate the next future occurrence
            print('[ReminderService] Recurring reminder "${reminder.message}" - calculating next occurrence');
            final intervalMinutes = reminder.intervalMinutes ?? 30;
            var nextTrigger = reminder.nextTrigger!;
            while (nextTrigger.isBefore(now)) {
              nextTrigger = nextTrigger.add(Duration(minutes: intervalMinutes));
            }
            final updatedReminder = reminder.copyWith(nextTrigger: nextTrigger);
            await _dbService.updateReminder(updatedReminder);
            await _scheduleReminderNotification(updatedReminder);
            continue;
          }
        }

        // Reminder is in the future, schedule it normally
        await _scheduleReminderNotification(reminder);
      }
    } catch (e) {
      print('[ReminderService] Error rescheduling reminders: $e');
    }
  }

  /// Schedule a notification for a reminder
  /// Android: Primary AndroidAlarmManager with TTS callback, fallback to zonedSchedule
  /// iOS: Use zonedSchedule for scheduled notifications
  Future<void> _scheduleReminderNotification(Reminder reminder) async {
    if (!reminder.isActive || reminder.nextTrigger == null) return;

    final now = DateTime.now();
    if (reminder.nextTrigger!.isBefore(now)) {
      // Trigger immediately if the time has passed
      await _triggerReminder(reminder);
      return;
    }

    final alarmId = reminder.id.hashCode.abs() % 100000;
    final notificationId = _baseNotificationId + alarmId % 10000;

    print('[ReminderService] ===== SCHEDULING NOTIFICATION =====');
    print('[ReminderService] Platform: ${Platform.isAndroid ? 'Android' : 'iOS'}');
    print('[ReminderService] Message: "${reminder.message}"');
    print('[ReminderService] Now (local): ${DateTime.now()}');
    print('[ReminderService] Target (DateTime): ${reminder.nextTrigger}');
    print('[ReminderService] Time until trigger: ${reminder.nextTrigger!.difference(DateTime.now()).inSeconds} seconds');
    print('[ReminderService] Alarm ID: $alarmId');
    print('[ReminderService] Notification ID: $notificationId');

    if (Platform.isAndroid) {
      // ANDROID: Try AndroidAlarmManager with TTS callback
      bool alarmScheduled = false;
      try {
        // Store reminder data for the callback to retrieve
        final prefs = await SharedPreferences.getInstance();
        final reminderData = jsonEncode({
          'id': reminder.id,
          'message': reminder.message,
          'isRecurring': reminder.type == ReminderType.recurring,
          'intervalMinutes': reminder.intervalMinutes,
          'scheduledTimeMs': reminder.nextTrigger!.millisecondsSinceEpoch,
        });
        await prefs.setString('alarm_$alarmId', reminderData);
        print('[ReminderService] Stored reminder data for alarm callback (scheduled: ${reminder.nextTrigger})');

        // Schedule the alarm with callback
        alarmScheduled = await AndroidAlarmManager.oneShotAt(
          reminder.nextTrigger!,
          alarmId,
          alarmCallback,
          exact: true,
          wakeup: true,
          rescheduleOnReboot: true,
          allowWhileIdle: true,
        );
        print('[ReminderService] AndroidAlarmManager scheduled: $alarmScheduled');
      } catch (e) {
        print('[ReminderService] AndroidAlarmManager failed: $e');
        alarmScheduled = false;
      }

      // FALLBACK: Use zonedSchedule if AlarmManager fails
      if (!alarmScheduled) {
        print('[ReminderService] Using fallback: zonedSchedule (no TTS)');
        await _scheduleFallbackNotification(reminder, notificationId);
      } else {
        // Also schedule fallback as backup - it will be cancelled if alarm fires
        print('[ReminderService] Scheduling fallback notification as backup');
        await _scheduleFallbackNotification(reminder, notificationId);
      }
    } else {
      // iOS: Use zonedSchedule for scheduled notifications
      print('[ReminderService] iOS: Using zonedSchedule');
      await _scheduleIOSNotification(reminder, notificationId);
    }

    print('[ReminderService] ================================');
  }

  /// Schedule notification for iOS using zonedSchedule
  Future<void> _scheduleIOSNotification(Reminder reminder, int notificationId) async {
    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      categoryIdentifier: reminder.type == ReminderType.recurring ? 'recurring_reminder' : 'one_time_reminder',
    );

    final notificationDetails = NotificationDetails(iOS: iosDetails);
    final scheduledDate = tz.TZDateTime.from(reminder.nextTrigger!, tz.local);

    await _notifications.zonedSchedule(
      notificationId,
      'Reminder: ${reminder.message}',
      reminder.message,
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: reminder.id,
    );
    print('[ReminderService] iOS notification scheduled for: $scheduledDate');
  }

  /// Fallback notification scheduling using flutter_local_notifications
  Future<void> _scheduleFallbackNotification(Reminder reminder, int notificationId) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: false,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      actions: reminder.type == ReminderType.recurring
          ? [
              const AndroidNotificationAction('snooze', 'Snooze 10min', cancelNotification: true),
              const AndroidNotificationAction('stop', 'Stop Reminder', cancelNotification: true),
            ]
          : [
              const AndroidNotificationAction('snooze', 'Snooze 10min', cancelNotification: true),
              const AndroidNotificationAction('dismiss', 'Dismiss', cancelNotification: true),
            ],
    );

    final notificationDetails = NotificationDetails(android: androidDetails);
    final scheduledDate = tz.TZDateTime.from(reminder.nextTrigger!, tz.local);

    await _notifications.zonedSchedule(
      notificationId,
      'Reminder: ${reminder.message}',
      reminder.message,
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: reminder.id,
    );
  }

  Future<void> _triggerReminder(Reminder reminder) async {
    print('[ReminderService] Triggering reminder: ${reminder.message}');

    // Show immediate notification
    await _showReminderNotification(reminder);

    // Speak the reminder
    await _speakReminder(reminder);

    // Update the reminder for next trigger or deactivate if one-time
    final updatedReminder = reminder.scheduleNextTrigger();
    await _dbService.updateReminder(updatedReminder);

    if (updatedReminder.type == ReminderType.oneTime) {
      print('[ReminderService] One-time reminder completed: ${reminder.message}');
    } else {
      print('[ReminderService] Recurring reminder rescheduled for: ${updatedReminder.nextTrigger}');
      // Schedule the next notification for recurring reminders
      await _scheduleReminderNotification(updatedReminder);
    }
  }

  Future<void> _showReminderNotification(Reminder reminder) async {
    final notificationId = _baseNotificationId + reminder.id.hashCode.abs() % 10000;

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: false,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      actions: reminder.type == ReminderType.recurring
          ? [
              const AndroidNotificationAction('snooze', 'Snooze 10min', cancelNotification: true),
              const AndroidNotificationAction('stop', 'Stop Reminder', cancelNotification: true),
            ]
          : [
              const AndroidNotificationAction('snooze', 'Snooze 10min', cancelNotification: true),
              const AndroidNotificationAction('dismiss', 'Dismiss', cancelNotification: true),
            ],
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notifications.show(
      notificationId,
      'Reminder: ${reminder.message}',
      reminder.message,
      notificationDetails,
      payload: reminder.id,
    );
  }

  Future<void> _speakReminder(Reminder reminder) async {
    try {
      await _tts.speak('Reminder: ${reminder.message}');
    } catch (e) {
      print('[ReminderService] Error speaking reminder: $e');
    }
  }

  /// Handle notification action (snooze, stop, dismiss)
  Future<void> handleNotificationAction(String action, String? reminderId) async {
    if (reminderId == null) return;

    final reminder = await _dbService.getReminderById(reminderId);
    if (reminder == null) return;

    switch (action) {
      case 'snooze':
        final snoozedReminder = reminder.snooze(minutes: 10);
        await _dbService.updateReminder(snoozedReminder);
        print('[ReminderService] Reminder snoozed for 10 minutes');
        break;

      case 'stop':
        await cancelReminder(reminderId);
        print('[ReminderService] Reminder stopped permanently');
        break;

      case 'dismiss':
        // For one-time reminders, just mark as inactive
        final dismissedReminder = reminder.copyWith(isActive: false);
        await _dbService.updateReminder(dismissedReminder);
        print('[ReminderService] Reminder dismissed');
        break;
    }
  }

  /// Create a new reminder
  Future<Reminder?> createReminder({
    required String userId,
    required String message,
    required ReminderType type,
    int? intervalMinutes,
    DateTime? scheduledTime,
    bool? isDurationBased,
  }) async {
    try {
      // Check for existing similar reminder
      final existing = await _dbService.findReminderByMessage(userId, message);
      if (existing != null) {
        // Cancel and delete the old one (replace)
        await cancelReminder(existing.id);
        print('[ReminderService] Replacing existing reminder: ${existing.message}');
      }

      // Calculate next trigger time
      DateTime nextTrigger;
      bool durationBased = isDurationBased ?? false;

      if (type == ReminderType.recurring && intervalMinutes != null) {
        nextTrigger = DateTime.now().add(Duration(minutes: intervalMinutes));
        durationBased = true; // Recurring reminders are always duration-based
      } else if (scheduledTime != null) {
        nextTrigger = scheduledTime;
        // If scheduledTime is set but isDurationBased is not explicitly provided,
        // check if it was created with "in X minutes" pattern (duration-based)
        // vs "at HH:MM" pattern (static time-based)
      } else {
        print('[ReminderService] Invalid reminder configuration');
        return null;
      }

      final reminder = Reminder(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: userId,
        message: message,
        type: type,
        intervalMinutes: intervalMinutes,
        scheduledTime: scheduledTime,
        nextTrigger: nextTrigger,
        isActive: true,
        createdAt: DateTime.now(),
        isDurationBased: durationBased,
      );

      await _dbService.saveReminder(reminder);
      print('[ReminderService] Created reminder: ${reminder.message} (durationBased: $durationBased)');

      // Schedule the notification
      await _scheduleReminderNotification(reminder);
      print('[ReminderService] Scheduled notification for: ${reminder.nextTrigger}');

      return reminder;
    } catch (e) {
      print('[ReminderService] Error creating reminder: $e');
      return null;
    }
  }

  /// Cancel a specific reminder
  Future<bool> cancelReminder(String reminderId) async {
    try {
      final alarmId = reminderId.hashCode.abs() % 100000;
      final notificationId = _baseNotificationId + alarmId % 10000;

      print('[ReminderService] Cancelling reminder: $reminderId (alarm: $alarmId)');

      // Cancel platform-specific alarm
      if (Platform.isAndroid) {
        // FIRST: Cancel the AndroidAlarmManager alarm to prevent it from firing
        // This must happen BEFORE deleting from DB to avoid race conditions
        await AndroidAlarmManager.cancel(alarmId);
        print('[ReminderService] Cancelled AndroidAlarmManager alarm: $alarmId');

        // Clean up ALL alarm-related data from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('alarm_$alarmId');

        // Also clear active alarm data if it matches this alarm
        final activeAlarmId = prefs.getInt('active_alarm_id');
        if (activeAlarmId == alarmId) {
          await prefs.remove('active_alarm_id');
          await prefs.remove('active_alarm_message');
          await prefs.remove('active_alarm_timestamp');
          await prefs.remove('active_alarm_reminder_id');
          print('[ReminderService] Cleared active alarm data for: $alarmId');
        }
      }

      // Cancel the notification (works on both platforms)
      await _notifications.cancel(notificationId);

      // FINALLY: Delete from database
      await _dbService.deleteReminder(reminderId);

      print('[ReminderService] Successfully cancelled reminder: $reminderId');
      return true;
    } catch (e) {
      print('[ReminderService] Error cancelling reminder: $e');
      return false;
    }
  }

  /// Cancel reminder by message (for voice cancellation)
  Future<bool> cancelReminderByMessage(String userId, String searchText) async {
    try {
      final reminder = await _dbService.findReminderByMessage(userId, searchText);
      if (reminder != null) {
        await cancelReminder(reminder.id);
        return true;
      }
      print('[ReminderService] No matching reminder found for: $searchText');
      return false;
    } catch (e) {
      print('[ReminderService] Error cancelling reminder by message: $e');
      return false;
    }
  }

  /// Cancel all reminders for a user
  Future<bool> cancelAllReminders(String userId) async {
    try {
      final reminders = await _dbService.getActiveRemindersByUserId(userId);

      print('[ReminderService] Cancelling ${reminders.length} reminders for user: $userId');

      for (final reminder in reminders) {
        final alarmId = reminder.id.hashCode.abs() % 100000;
        final notificationId = _baseNotificationId + alarmId % 10000;

        // Cancel platform-specific alarm
        if (Platform.isAndroid) {
          await AndroidAlarmManager.cancel(alarmId);

          // Clean up alarm data from SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('alarm_$alarmId');
        }

        // Cancel notification (works on both platforms)
        await _notifications.cancel(notificationId);

        print('[ReminderService] Cancelled reminder: ${reminder.message} (alarm: $alarmId)');
      }

      // Clear any active alarm data (Android only)
      if (Platform.isAndroid) {
        final prefs = await SharedPreferences.getInstance();
        final activeAlarmReminderId = prefs.getString('active_alarm_reminder_id');
        if (activeAlarmReminderId != null) {
          await prefs.remove('active_alarm_id');
          await prefs.remove('active_alarm_message');
          await prefs.remove('active_alarm_timestamp');
          await prefs.remove('active_alarm_reminder_id');
          print('[ReminderService] Cleared active alarm data');
        }
      }

      await _dbService.deleteAllRemindersForUser(userId);
      print('[ReminderService] Successfully cancelled all reminders for user: $userId');
      return true;
    } catch (e) {
      print('[ReminderService] Error cancelling all reminders: $e');
      return false;
    }
  }

  /// Get all active reminders for a user
  Future<List<Reminder>> getActiveReminders(String userId) async {
    return await _dbService.getActiveRemindersByUserId(userId);
  }

  /// Get all reminders for a user (including inactive)
  Future<List<Reminder>> getAllReminders(String userId) async {
    return await _dbService.getRemindersByUserId(userId);
  }

  /// Update an existing reminder
  Future<bool> updateReminder(Reminder reminder) async {
    return await _dbService.updateReminder(reminder);
  }

  /// Get all reminders (active and past) for a user
  Future<List<Reminder>> getAllRemindersWithPast(String userId) async {
    return await _dbService.getAllRemindersByUserId(userId);
  }

  /// Get past/triggered reminders for a user
  Future<List<Reminder>> getPastReminders(String userId) async {
    return await _dbService.getPastRemindersByUserId(userId);
  }

  /// Mark a reminder as triggered (move to past reminders)
  Future<bool> markReminderAsTriggered(String reminderId) async {
    try {
      final reminder = await _dbService.getReminderById(reminderId);
      if (reminder == null) return false;

      final triggeredReminder = reminder.copyWith(
        isActive: false,
        triggeredAt: DateTime.now(),
      );
      await _dbService.updateReminder(triggeredReminder);

      // Cancel any scheduled notifications/alarms
      final alarmId = reminderId.hashCode.abs() % 100000;
      final notificationId = _baseNotificationId + alarmId % 10000;

      // Cancel notification on both platforms
      await _notifications.cancel(notificationId);

      // Android-specific cleanup
      if (Platform.isAndroid) {
        await _cleanupAlarmData(alarmId);
      }

      print('[ReminderService] Marked reminder as triggered: ${reminder.message}');
      return true;
    } catch (e) {
      print('[ReminderService] Error marking reminder as triggered: $e');
      return false;
    }
  }

  /// Make a reminder recurring with specified interval
  /// intervalMinutes: null means use the original duration (for "Yes" option)
  Future<Reminder?> makeReminderRecurring(String reminderId, {int? intervalMinutes}) async {
    try {
      print('[ReminderService] makeReminderRecurring called for: $reminderId, intervalMinutes: $intervalMinutes');

      final reminder = await _dbService.getReminderById(reminderId);
      if (reminder == null) {
        print('[ReminderService] Reminder not found: $reminderId');
        return null;
      }

      print('[ReminderService] Found reminder: ${reminder.message}, isDurationBased: ${reminder.isDurationBased}, intervalMinutes: ${reminder.intervalMinutes}');
      print('[ReminderService] Reminder createdAt: ${reminder.createdAt}, nextTrigger: ${reminder.nextTrigger}');

      // Determine the interval:
      // Priority order:
      // 1. Explicitly provided intervalMinutes parameter
      // 2. Stored intervalMinutes from the reminder (set during creation for duration-based reminders)
      // 3. Calculate from original duration (time between creation and next trigger)
      // 4. Default to 30 minutes
      int interval;

      if (intervalMinutes != null) {
        // Explicit interval provided by caller
        interval = intervalMinutes;
        print('[ReminderService] Using provided interval: $interval minutes');
      } else if (reminder.intervalMinutes != null && reminder.intervalMinutes! > 0) {
        // Use stored interval from reminder (this preserves the original "in X minutes" duration)
        interval = reminder.intervalMinutes!;
        print('[ReminderService] Using stored interval from reminder: $interval minutes');
      } else if (reminder.isDurationBased) {
        // Calculate from timestamps as fallback
        final originalDuration = reminder.nextTrigger.difference(reminder.createdAt);
        // Use inSeconds and convert to get better precision for short durations
        final totalSeconds = originalDuration.inSeconds;
        interval = (totalSeconds / 60).ceil(); // Round up to ensure at least 1 minute
        print('[ReminderService] Calculated interval from duration: $interval minutes (${totalSeconds}s)');
        if (interval <= 0) interval = 1; // Minimum 1 minute
      } else {
        // Default fallback
        interval = 30;
        print('[ReminderService] Using default interval: $interval minutes');
      }

      final nextTrigger = DateTime.now().add(Duration(minutes: interval));
      print('[ReminderService] Setting next trigger to: $nextTrigger (in $interval minutes)');

      final recurringReminder = reminder.copyWith(
        type: ReminderType.recurring,
        intervalMinutes: interval,
        isActive: true,
        nextTrigger: nextTrigger,
        triggeredAt: null, // Clear triggered time since it's active again
      );

      await _dbService.updateReminder(recurringReminder);
      print('[ReminderService] Updated reminder in database');

      await _scheduleReminderNotification(recurringReminder);
      print('[ReminderService] Scheduled recurring notification');

      print('[ReminderService] Made reminder recurring: ${reminder.message} (every $interval minutes, next: $nextTrigger)');
      return recurringReminder;
    } catch (e, stack) {
      print('[ReminderService] Error making reminder recurring: $e');
      print('[ReminderService] Stack trace: $stack');
      return null;
    }
  }

  /// Get reminder by ID
  Future<Reminder?> getReminderById(String reminderId) async {
    return await _dbService.getReminderById(reminderId);
  }

  /// Parse reminder from voice input
  /// Returns a map with 'type', 'message', 'intervalMinutes', 'scheduledTime'
  static Map<String, dynamic>? parseReminderFromVoice(String input) {
    final lowerInput = input.toLowerCase().trim();

    // Check if it's a reminder creation command
    if (!lowerInput.contains('remind')) {
      return null;
    }

    // Patterns for recurring reminders
    // "remind me to X every N minutes/hours"
    final recurringPattern = RegExp(
      r'remind(?:\s+me)?\s+to\s+(.+?)\s+every\s+(\d+)\s*(minutes?|mins?|hours?|hrs?)',
      caseSensitive: false,
    );

    final recurringMatch = recurringPattern.firstMatch(lowerInput);
    if (recurringMatch != null) {
      final message = recurringMatch.group(1)?.trim() ?? '';
      final amount = int.tryParse(recurringMatch.group(2) ?? '0') ?? 0;
      final unit = recurringMatch.group(3)?.toLowerCase() ?? '';

      int intervalMinutes = amount;
      if (unit.startsWith('hour') || unit.startsWith('hr')) {
        intervalMinutes = amount * 60;
      }

      return {
        'type': ReminderType.recurring,
        'message': _capitalizeFirst(message),
        'intervalMinutes': intervalMinutes,
        'scheduledTime': null,
        'isDurationBased': true,
      };
    }

    // Patterns for one-time reminders
    // "remind me to X at HH:MM" or "remind me to X at H PM/AM"
    final atTimePattern = RegExp(
      r'remind(?:\s+me)?\s+to\s+(.+?)\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?',
      caseSensitive: false,
    );

    final atTimeMatch = atTimePattern.firstMatch(lowerInput);
    if (atTimeMatch != null) {
      final message = atTimeMatch.group(1)?.trim() ?? '';
      var hour = int.tryParse(atTimeMatch.group(2) ?? '0') ?? 0;
      final minute = int.tryParse(atTimeMatch.group(3) ?? '0') ?? 0;
      final ampm = atTimeMatch.group(4)?.toLowerCase();

      // Convert to 24-hour format
      if (ampm == 'pm' && hour != 12) {
        hour += 12;
      } else if (ampm == 'am' && hour == 12) {
        hour = 0;
      }

      final now = DateTime.now();
      var scheduledTime = DateTime(now.year, now.month, now.day, hour, minute);

      // If the time has already passed today, schedule for tomorrow
      if (scheduledTime.isBefore(now)) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      return {
        'type': ReminderType.oneTime,
        'message': _capitalizeFirst(message),
        'intervalMinutes': null,
        'scheduledTime': scheduledTime,
        'isDurationBased': false, // "at HH:MM" is static time-based
      };
    }

    // "remind me to X in N minutes/hours" or "remind me to X after N minutes/hours"
    final inDurationPattern = RegExp(
      r'remind(?:\s+me)?\s+to\s+(.+?)\s+(?:in|after)\s+(\d+)\s*(minutes?|mins?|hours?|hrs?|seconds?|secs?)',
      caseSensitive: false,
    );

    final inDurationMatch = inDurationPattern.firstMatch(lowerInput);
    if (inDurationMatch != null) {
      final message = inDurationMatch.group(1)?.trim() ?? '';
      final amount = int.tryParse(inDurationMatch.group(2) ?? '0') ?? 0;
      final unit = inDurationMatch.group(3)?.toLowerCase() ?? '';

      int minutes = amount;
      if (unit.startsWith('hour') || unit.startsWith('hr')) {
        minutes = amount * 60;
      } else if (unit.startsWith('second') || unit.startsWith('sec')) {
        // Convert seconds to minutes (minimum 1 minute)
        minutes = (amount / 60).ceil();
        if (minutes < 1) minutes = 1;
      }

      final scheduledTime = DateTime.now().add(Duration(minutes: minutes));

      return {
        'type': ReminderType.oneTime,
        'message': _capitalizeFirst(message),
        'intervalMinutes': minutes, // Store the duration for potential recurring conversion
        'scheduledTime': scheduledTime,
        'isDurationBased': true, // "in X minutes" is duration-based
      };
    }

    return null;
  }

  /// Parse cancel reminder command
  /// Returns null if not a cancel command, or the search text to find the reminder
  static String? parseCancelCommand(String input) {
    final lowerInput = input.toLowerCase().trim();

    // "stop all reminders" or "cancel all reminders"
    if (lowerInput.contains('all reminder') ||
        lowerInput.contains('all my reminder')) {
      return '__ALL__';
    }

    // "cancel my X reminder" or "stop the X reminder"
    final cancelPattern = RegExp(
      r'(?:cancel|stop|remove|delete)(?:\s+my|\s+the)?\s+(.+?)\s*reminder',
      caseSensitive: false,
    );

    final match = cancelPattern.firstMatch(lowerInput);
    if (match != null) {
      return match.group(1)?.trim();
    }

    return null;
  }

  static String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  /// Get timezone name from offset (common timezones)
  String _getTimezoneNameFromOffset(Duration offset) {
    final hours = offset.inHours;
    final minutes = offset.inMinutes % 60;

    // Map common timezone offsets to IANA timezone names
    // This covers major timezones - India is UTC+5:30
    final Map<String, String> offsetToTimezone = {
      '5:30': 'Asia/Kolkata',      // India
      '5:45': 'Asia/Kathmandu',    // Nepal
      '0:0': 'UTC',                // UTC
      '1:0': 'Europe/Paris',       // CET
      '2:0': 'Europe/Athens',      // EET
      '3:0': 'Europe/Moscow',      // MSK
      '4:0': 'Asia/Dubai',         // GST
      '5:0': 'Asia/Karachi',       // PKT
      '6:0': 'Asia/Dhaka',         // BST
      '7:0': 'Asia/Bangkok',       // ICT
      '8:0': 'Asia/Singapore',     // SGT
      '9:0': 'Asia/Tokyo',         // JST
      '9:30': 'Australia/Darwin',  // ACST
      '10:0': 'Australia/Sydney',  // AEST
      '11:0': 'Pacific/Noumea',    // NCT
      '12:0': 'Pacific/Auckland',  // NZST
      '-5:0': 'America/New_York',  // EST
      '-6:0': 'America/Chicago',   // CST
      '-7:0': 'America/Denver',    // MST
      '-8:0': 'America/Los_Angeles', // PST
      '-3:0': 'America/Sao_Paulo', // BRT
      '-4:0': 'America/Halifax',   // AST
    };

    final key = '$hours:${minutes.abs()}';
    return offsetToTimezone[key] ?? 'Asia/Kolkata'; // Default to India if not found
  }

  /// Stop the reminder check timer
  void dispose() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }
}
