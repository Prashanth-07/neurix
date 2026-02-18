import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/reminder_model.dart';
import '../services/auth_service.dart';
import '../services/reminder_service.dart';
import '../utils/constants.dart';
import '../widgets/starfield_background.dart';
import '../widgets/glass_card.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({Key? key}) : super(key: key);

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final ReminderService _reminderService = ReminderService();
  List<Reminder> _activeReminders = [];
  List<Reminder> _pastReminders = [];
  bool _isLoading = true;
  bool _isPastExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.uid ?? 'anonymous';

      final allReminders = await _reminderService.getAllRemindersWithPast(userId);

      final now = DateTime.now();
      final active = <Reminder>[];
      final past = <Reminder>[];

      for (final reminder in allReminders) {
        if (reminder.isActive) {
          if (reminder.type == ReminderType.recurring ||
              reminder.nextTrigger.isAfter(now)) {
            active.add(reminder);
          } else {
            past.add(reminder);
          }
        } else {
          past.add(reminder);
        }
      }

      active.sort((a, b) => a.nextTrigger.compareTo(b.nextTrigger));

      past.sort((a, b) {
        final aTime = a.triggeredAt ?? a.nextTrigger;
        final bTime = b.triggeredAt ?? b.nextTrigger;
        return bTime.compareTo(aTime);
      });

      setState(() {
        _activeReminders = active;
        _pastReminders = past;
        _isLoading = false;
      });
    } catch (e) {
      print('[RemindersScreen] Error loading reminders: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Reminder', style: TextStyle(color: AppColors.text)),
        content: Text('Are you sure you want to delete the reminder "${reminder.message}"?', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _reminderService.cancelReminder(reminder.id);
      await _loadReminders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder deleted'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _editReminder(Reminder reminder) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditReminderDialog(reminder: reminder),
    );

    if (result != null) {
      final updatedReminder = reminder.copyWith(
        message: result['message'] as String,
        intervalMinutes: result['intervalMinutes'] as int?,
      );

      final finalReminder = updatedReminder.type == ReminderType.recurring &&
              updatedReminder.intervalMinutes != null
          ? updatedReminder.copyWith(
              nextTrigger: DateTime.now()
                  .add(Duration(minutes: updatedReminder.intervalMinutes!)),
            )
          : updatedReminder;

      await _reminderService.updateReminder(finalReminder);
      await _loadReminders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder updated'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _addReminder() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _AddReminderDialog(),
    );

    if (result != null) {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.uid ?? 'anonymous';

      await _reminderService.createReminder(
        userId: userId,
        message: result['message'] as String,
        type: result['type'] as ReminderType,
        intervalMinutes: result['intervalMinutes'] as int?,
        scheduledTime: result['scheduledTime'] as DateTime?,
        isDurationBased: result['isDurationBased'] as bool?,
      );

      await _loadReminders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder created'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Reminders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: _loadReminders,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addReminder,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StarfieldBackground(
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _activeReminders.isEmpty && _pastReminders.isEmpty
                  ? _buildEmptyState()
                  : _buildReminderList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 80,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 16),
          Text(
            'No reminders yet',
            style: AppTextStyles.subheading.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap + to add a reminder or say\n"Remind me to drink water every hour"',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildReminderList() {
    return RefreshIndicator(
      onRefresh: _loadReminders,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(AppSizes.paddingMedium),
        children: [
          // Active reminders section
          if (_activeReminders.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.paddingSmall),
              child: Text(
                'Active Reminders (${_activeReminders.length})',
                style: AppTextStyles.subheading,
              ),
            ),
            ..._activeReminders.map((reminder) => _buildReminderCard(reminder, isActive: true)),
          ],

          // Empty state for active reminders
          if (_activeReminders.isEmpty && _pastReminders.isNotEmpty) ...[
            GlassCard(
              margin: const EdgeInsets.only(bottom: AppSizes.paddingMedium),
              child: Column(
                children: [
                  Icon(Icons.notifications_none, size: 40, color: AppColors.textHint),
                  const SizedBox(height: 8),
                  Text(
                    'No active reminders',
                    style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],

          // Past reminders section (collapsible)
          if (_pastReminders.isNotEmpty) ...[
            const SizedBox(height: AppSizes.paddingMedium),
            InkWell(
              onTap: () {
                setState(() {
                  _isPastExpanded = !_isPastExpanded;
                });
              },
              borderRadius: BorderRadius.circular(AppSizes.borderRadius),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSizes.paddingSmall),
                child: Row(
                  children: [
                    Icon(
                      _isPastExpanded ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Past Reminders (${_pastReminders.length})',
                      style: AppTextStyles.subheading.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            if (_isPastExpanded) ...[
              const SizedBox(height: AppSizes.paddingSmall),
              ..._pastReminders.map((reminder) => _buildReminderCard(reminder, isActive: false)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildReminderCard(Reminder reminder, {required bool isActive}) {
    final isRecurring = reminder.type == ReminderType.recurring;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.paddingSmall),
      child: GlassCard(
        onTap: isActive ? () => _editReminder(reminder) : null,
        backgroundColor: isActive ? null : Colors.white.withOpacity(0.03),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isActive
                    ? (isRecurring ? AppColors.info.withOpacity(0.12) : AppColors.warning.withOpacity(0.12))
                    : AppColors.glass,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isRecurring ? Icons.repeat : Icons.notifications_active,
                color: isActive
                    ? (isRecurring ? AppColors.info : AppColors.warning)
                    : AppColors.textHint,
              ),
            ),
            const SizedBox(width: AppSizes.paddingMedium),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reminder.message,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isActive ? AppColors.text : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reminder.formattedSchedule,
                    style: AppTextStyles.caption.copyWith(
                      color: isActive
                          ? (isRecurring ? AppColors.info : AppColors.warning)
                          : AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isActive
                        ? 'Next: ${reminder.formattedNextTrigger}'
                        : 'Triggered: ${_formatTriggeredTime(reminder.triggeredAt ?? reminder.nextTrigger)}',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            // Delete button
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: isActive ? AppColors.error.withOpacity(0.7) : AppColors.textHint,
              ),
              onPressed: () => _deleteReminder(reminder),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTriggeredTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }
}

class _EditReminderDialog extends StatefulWidget {
  final Reminder reminder;

  const _EditReminderDialog({required this.reminder});

  @override
  State<_EditReminderDialog> createState() => _EditReminderDialogState();
}

class _EditReminderDialogState extends State<_EditReminderDialog> {
  late TextEditingController _messageController;
  late TextEditingController _intervalController;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController(text: widget.reminder.message);
    _intervalController = TextEditingController(
      text: widget.reminder.intervalMinutes?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRecurring = widget.reminder.type == ReminderType.recurring;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Edit Reminder', style: TextStyle(color: AppColors.text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _messageController,
              style: const TextStyle(color: AppColors.text),
              decoration: AppInputDecorations.textField(
                label: 'Message',
                icon: Icons.message_outlined,
                hintText: 'What to remind you about',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            if (isRecurring) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _intervalController,
                style: const TextStyle(color: AppColors.text),
                decoration: AppInputDecorations.textField(
                  label: 'Interval (minutes)',
                  icon: Icons.timer_outlined,
                  hintText: 'e.g., 30',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final message = _messageController.text.trim();
            if (message.isEmpty) return;

            final interval = int.tryParse(_intervalController.text);

            Navigator.pop(context, {
              'message': message,
              'intervalMinutes': isRecurring ? interval : null,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _AddReminderDialog extends StatefulWidget {
  const _AddReminderDialog();

  @override
  State<_AddReminderDialog> createState() => _AddReminderDialogState();
}

class _AddReminderDialogState extends State<_AddReminderDialog> {
  final _messageController = TextEditingController();
  final _intervalController = TextEditingController();
  ReminderType _type = ReminderType.recurring;
  TimeOfDay? _scheduledTime;

  @override
  void dispose() {
    _messageController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (time != null) {
      setState(() => _scheduledTime = time);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Add Reminder', style: TextStyle(color: AppColors.text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _messageController,
              style: const TextStyle(color: AppColors.text),
              decoration: AppInputDecorations.textField(
                label: 'Message',
                icon: Icons.message_outlined,
                hintText: 'What to remind you about',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            const Text('Type:', style: TextStyle(color: AppColors.textSecondary)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<ReminderType>(
                    title: const Text('Recurring', style: TextStyle(color: AppColors.text, fontSize: 14)),
                    value: ReminderType.recurring,
                    groupValue: _type,
                    onChanged: (value) => setState(() => _type = value!),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppColors.primary,
                  ),
                ),
                Expanded(
                  child: RadioListTile<ReminderType>(
                    title: const Text('One-time', style: TextStyle(color: AppColors.text, fontSize: 14)),
                    value: ReminderType.oneTime,
                    groupValue: _type,
                    onChanged: (value) => setState(() => _type = value!),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_type == ReminderType.recurring)
              TextField(
                controller: _intervalController,
                style: const TextStyle(color: AppColors.text),
                decoration: AppInputDecorations.textField(
                  label: 'Interval (minutes)',
                  icon: Icons.timer_outlined,
                  hintText: 'e.g., 30 for every 30 minutes',
                ),
                keyboardType: TextInputType.number,
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _scheduledTime != null
                      ? 'At ${_scheduledTime!.format(context)}'
                      : 'Select time',
                  style: const TextStyle(color: AppColors.text),
                ),
                trailing: const Icon(Icons.access_time, color: AppColors.primary),
                onTap: _selectTime,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final message = _messageController.text.trim();
            if (message.isEmpty) return;

            if (_type == ReminderType.recurring) {
              final interval = int.tryParse(_intervalController.text);
              if (interval == null || interval <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid interval')),
                );
                return;
              }

              Navigator.pop(context, {
                'message': message,
                'type': _type,
                'intervalMinutes': interval,
                'scheduledTime': null,
                'isDurationBased': true,
              });
            } else {
              if (_scheduledTime == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please select a time')),
                );
                return;
              }

              final now = DateTime.now();
              var scheduledDateTime = DateTime(
                now.year,
                now.month,
                now.day,
                _scheduledTime!.hour,
                _scheduledTime!.minute,
              );

              if (scheduledDateTime.isBefore(now)) {
                scheduledDateTime = scheduledDateTime.add(const Duration(days: 1));
              }

              Navigator.pop(context, {
                'message': message,
                'type': _type,
                'intervalMinutes': null,
                'scheduledTime': scheduledDateTime,
                'isDurationBased': false,
              });
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
