enum ReminderType {
  recurring,
  oneTime,
}

class Reminder {
  final String id;
  final String userId;
  final String message;
  final ReminderType type;
  final int? intervalMinutes; // For recurring reminders
  final DateTime? scheduledTime; // For one-time reminders
  final DateTime nextTrigger;
  final bool isActive;
  final DateTime createdAt;

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
  });

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
