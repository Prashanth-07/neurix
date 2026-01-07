enum ReminderType {
  recurring,
  oneTime,
}

class Reminder {
  final String id;
  final String userId;
  final String message;
  final ReminderType type;
  final int? intervalMinutes; // For recurring reminders (duration in minutes)
  final DateTime? scheduledTime; // For one-time reminders (static time)
  final DateTime nextTrigger;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? triggeredAt; // When the reminder was last triggered
  final bool isDurationBased; // true if created with duration (e.g., "in 30 minutes")

  Reminder({
    required this.id,
    required this.userId,
    required this.message,
    required this.type,
    this.intervalMinutes,
    this.scheduledTime,
    required this.nextTrigger,
    this.isActive = true,
    required this.createdAt,
    this.triggeredAt,
    this.isDurationBased = false,
  });

  /// Check if this is a past/triggered reminder that should go in the dropdown
  bool get isPastReminder {
    // If it's inactive and was triggered, it's a past reminder
    if (!isActive && triggeredAt != null) return true;
    // If it's a one-time reminder and the time has passed
    if (type == ReminderType.oneTime && !isActive) return true;
    return false;
  }

  /// Check if this is an active/upcoming reminder
  bool get isUpcomingReminder {
    // Recurring reminders are always upcoming (unless manually deactivated)
    if (type == ReminderType.recurring && isActive) return true;
    // One-time reminders are upcoming if active and next trigger is in the future
    if (type == ReminderType.oneTime && isActive && nextTrigger.isAfter(DateTime.now())) return true;
    return false;
  }

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      message: map['message'] ?? '',
      type: map['type'] == 'recurring' ? ReminderType.recurring : ReminderType.oneTime,
      intervalMinutes: map['interval_minutes'],
      scheduledTime: map['scheduled_time'] != null
          ? DateTime.parse(map['scheduled_time'])
          : null,
      nextTrigger: DateTime.parse(map['next_trigger'] ?? DateTime.now().toIso8601String()),
      isActive: map['is_active'] == 1 || map['is_active'] == true,
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      triggeredAt: map['triggered_at'] != null
          ? DateTime.parse(map['triggered_at'])
          : null,
      isDurationBased: map['is_duration_based'] == 1 || map['is_duration_based'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'message': message,
      'type': type == ReminderType.recurring ? 'recurring' : 'one_time',
      'interval_minutes': intervalMinutes,
      'scheduled_time': scheduledTime?.toIso8601String(),
      'next_trigger': nextTrigger.toIso8601String(),
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'triggered_at': triggeredAt?.toIso8601String(),
      'is_duration_based': isDurationBased ? 1 : 0,
    };
  }

  Reminder copyWith({
    String? id,
    String? userId,
    String? message,
    ReminderType? type,
    int? intervalMinutes,
    DateTime? scheduledTime,
    DateTime? nextTrigger,
    bool? isActive,
    DateTime? createdAt,
    DateTime? triggeredAt,
    bool? isDurationBased,
  }) {
    return Reminder(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      message: message ?? this.message,
      type: type ?? this.type,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      nextTrigger: nextTrigger ?? this.nextTrigger,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      isDurationBased: isDurationBased ?? this.isDurationBased,
    );
  }

  /// Calculate the next trigger time for recurring reminders
  Reminder scheduleNextTrigger() {
    if (type == ReminderType.recurring && intervalMinutes != null) {
      final newNextTrigger = DateTime.now().add(Duration(minutes: intervalMinutes!));
      return copyWith(nextTrigger: newNextTrigger);
    }
    // One-time reminders become inactive after triggering
    return copyWith(isActive: false);
  }

  /// Snooze the reminder by a specified duration
  Reminder snooze({int minutes = 10}) {
    final newNextTrigger = DateTime.now().add(Duration(minutes: minutes));
    return copyWith(nextTrigger: newNextTrigger);
  }

  String get formattedSchedule {
    if (type == ReminderType.recurring && intervalMinutes != null) {
      if (intervalMinutes! >= 60) {
        final hours = intervalMinutes! ~/ 60;
        final mins = intervalMinutes! % 60;
        if (mins == 0) {
          return 'Every ${hours} hour${hours > 1 ? 's' : ''}';
        }
        return 'Every ${hours}h ${mins}m';
      }
      return 'Every $intervalMinutes minute${intervalMinutes! > 1 ? 's' : ''}';
    } else if (scheduledTime != null) {
      final now = DateTime.now();
      final isToday = scheduledTime!.day == now.day &&
          scheduledTime!.month == now.month &&
          scheduledTime!.year == now.year;
      final isTomorrow = scheduledTime!.day == now.day + 1 &&
          scheduledTime!.month == now.month &&
          scheduledTime!.year == now.year;

      final timeStr = '${scheduledTime!.hour.toString().padLeft(2, '0')}:${scheduledTime!.minute.toString().padLeft(2, '0')}';

      if (isToday) {
        return 'Today at $timeStr';
      } else if (isTomorrow) {
        return 'Tomorrow at $timeStr';
      }
      return '${scheduledTime!.day}/${scheduledTime!.month} at $timeStr';
    }
    return 'One-time';
  }

  String get formattedNextTrigger {
    final now = DateTime.now();
    final diff = nextTrigger.difference(now);

    if (diff.isNegative) {
      return 'Overdue';
    } else if (diff.inMinutes < 1) {
      return 'In less than a minute';
    } else if (diff.inMinutes < 60) {
      return 'In ${diff.inMinutes} minute${diff.inMinutes > 1 ? 's' : ''}';
    } else if (diff.inHours < 24) {
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      if (mins == 0) {
        return 'In $hours hour${hours > 1 ? 's' : ''}';
      }
      return 'In ${hours}h ${mins}m';
    }
    final timeStr = '${nextTrigger.hour.toString().padLeft(2, '0')}:${nextTrigger.minute.toString().padLeft(2, '0')}';
    return '${nextTrigger.day}/${nextTrigger.month} at $timeStr';
  }

  @override
  String toString() {
    return 'Reminder(id: $id, message: $message, type: $type, isActive: $isActive)';
  }
}
