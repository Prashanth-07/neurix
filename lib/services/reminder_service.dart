import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../models/reminder_model.dart';
import 'local_db_service.dart';

/// Top-level callback for AndroidAlarmManager - runs in isolate when alarm fires
/// This enables TTS to speak when the notification triggers
@pragma('vm:entry-point')
Future<void> alarmCallback(int alarmId) async {
  print('[AlarmCallback] ===== ALARM FIRED =====');
  print('[AlarmCallback] Alarm ID: $alarmId');

  try {
    // Ensure Flutter bindings are initialized for background isolate
    DartPluginRegistrant.ensureInitialized();

    // Get reminder data from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final reminderJson = prefs.getString('alarm_$alarmId');

    if (reminderJson == null) {
      print('[AlarmCallback] No reminder data found for alarm $alarmId');
      return;
    }

    final reminderData = jsonDecode(reminderJson) as Map<String, dynamic>;
    final message = reminderData['message'] as String? ?? 'Reminder';
    final reminderId = reminderData['id'] as String? ?? '';
    final isRecurring = reminderData['isRecurring'] as bool? ?? false;
    final intervalMinutes = reminderData['intervalMinutes'] as int?;

    print('[AlarmCallback] Message: "$message"');
    print('[AlarmCallback] Is Recurring: $isRecurring');

    // Initialize and show notification
    final notifications = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await notifications.initialize(initSettings);

    final notificationId = 1000 + alarmId % 10000;
    final androidDetails = AndroidNotificationDetails(
      'neurix_reminders',
      'Neurix Reminders',
      channelDescription: 'Reminder notifications',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: false,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
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
      payload: reminderId,
    );
    print('[AlarmCallback] Notification shown');

    // Speak the reminder using TTS
    try {
      final tts = FlutterTts();
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.5);
      await tts.setVolume(1.0);
      await tts.awaitSpeakCompletion(true);
      await tts.speak('Reminder: $message');
      print('[AlarmCallback] TTS completed');
    } catch (ttsError) {
      print('[AlarmCallback] TTS error (non-fatal): $ttsError');
    }

    // For recurring reminders, schedule the next alarm
    if (isRecurring && intervalMinutes != null && intervalMinutes > 0) {
      final nextAlarmTime = DateTime.now().add(Duration(minutes: intervalMinutes));
      print('[AlarmCallback] Scheduling next recurring alarm for: $nextAlarmTime');

      await AndroidAlarmManager.oneShotAt(
        nextAlarmTime,
        alarmId,
        alarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
        allowWhileIdle: true,
      );
    } else {
      // Clean up one-time reminder data
      await prefs.remove('alarm_$alarmId');
      print('[AlarmCallback] One-time reminder completed, cleaned up');
    }

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

    // Initialize Android Alarm Manager for background scheduling
    await AndroidAlarmManager.initialize();

    // Initialize notifications with callback for handling actions
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create notification channel
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

    // Reschedule any active reminders on app start
    await _rescheduleAllActiveReminders();

    _isInitialized = true;
    print('[ReminderService] Initialized with AlarmManager');
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

  /// Reschedule all active reminders (called on app start)
  Future<void> _rescheduleAllActiveReminders() async {
    try {
      final reminders = await _dbService.getAllActiveReminders();
      print('[ReminderService] Rescheduling ${reminders.length} active reminders');

      for (final reminder in reminders) {
        await _scheduleReminderNotification(reminder);
      }
    } catch (e) {
      print('[ReminderService] Error rescheduling reminders: $e');
    }
  }

  /// Schedule a notification for a reminder
  /// Primary: AndroidAlarmManager with TTS callback
  /// Fallback: flutter_local_notifications zonedSchedule (no TTS)
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
    print('[ReminderService] Message: "${reminder.message}"');
    print('[ReminderService] Now (local): ${DateTime.now()}');
    print('[ReminderService] Target (DateTime): ${reminder.nextTrigger}');
    print('[ReminderService] Time until trigger: ${reminder.nextTrigger!.difference(DateTime.now()).inSeconds} seconds');
    print('[ReminderService] Alarm ID: $alarmId');
    print('[ReminderService] Notification ID: $notificationId');

    // PRIMARY: Try AndroidAlarmManager with TTS callback
    bool alarmScheduled = false;
    try {
      // Store reminder data for the callback to retrieve
      final prefs = await SharedPreferences.getInstance();
      final reminderData = jsonEncode({
        'id': reminder.id,
        'message': reminder.message,
        'isRecurring': reminder.type == ReminderType.recurring,
        'intervalMinutes': reminder.intervalMinutes,
      });
      await prefs.setString('alarm_$alarmId', reminderData);
      print('[ReminderService] Stored reminder data for alarm callback');

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
    // This ensures notification shows even if TTS doesn't work
    if (!alarmScheduled) {
      print('[ReminderService] Using fallback: zonedSchedule (no TTS)');
      await _scheduleFallbackNotification(reminder, notificationId);
    } else {
      // Also schedule fallback as backup - it will be cancelled if alarm fires
      print('[ReminderService] Scheduling fallback notification as backup');
      await _scheduleFallbackNotification(reminder, notificationId);
    }

    print('[ReminderService] ================================');
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
      if (type == ReminderType.recurring && intervalMinutes != null) {
        nextTrigger = DateTime.now().add(Duration(minutes: intervalMinutes));
      } else if (scheduledTime != null) {
        nextTrigger = scheduledTime;
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
      );

      await _dbService.saveReminder(reminder);
      print('[ReminderService] Created reminder: ${reminder.message}');

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
      await _dbService.deleteReminder(reminderId);

      final alarmId = reminderId.hashCode.abs() % 100000;
      final notificationId = _baseNotificationId + alarmId % 10000;

      // Cancel the AndroidAlarmManager alarm
      await AndroidAlarmManager.cancel(alarmId);

      // Cancel the notification
      await _notifications.cancel(notificationId);

      // Clean up stored alarm data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('alarm_$alarmId');

      print('[ReminderService] Cancelled reminder: $reminderId (alarm: $alarmId)');
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

      for (final reminder in reminders) {
        final notificationId = _baseNotificationId + reminder.id.hashCode.abs() % 10000;
        await _notifications.cancel(notificationId);
      }

      await _dbService.deleteAllRemindersForUser(userId);
      print('[ReminderService] Cancelled all reminders for user: $userId');
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
        'intervalMinutes': null,
        'scheduledTime': scheduledTime,
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
