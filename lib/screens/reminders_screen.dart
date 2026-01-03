import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/reminder_model.dart';
import '../services/auth_service.dart';
import '../services/reminder_service.dart';
import '../utils/constants.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({Key? key}) : super(key: key);

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final ReminderService _reminderService = ReminderService();
  List<Reminder> _reminders = [];
  bool _isLoading = true;

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

      final reminders = await _reminderService.getActiveReminders(userId);

      setState(() {
        _reminders = reminders;
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
        title: const Text('Delete Reminder'),
        content: Text('Are you sure you want to delete the reminder "${reminder.message}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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

      // Recalculate next trigger if interval changed
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
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReminders,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addReminder,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reminders.isEmpty
              ? _buildEmptyState()
              : _buildReminderList(),
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
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No reminders yet',
            style: AppTextStyles.subheading.copyWith(color: Colors.grey[600]),
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
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSizes.paddingMedium),
        itemCount: _reminders.length,
        itemBuilder: (context, index) {
          final reminder = _reminders[index];
          return _buildReminderCard(reminder);
        },
      ),
    );
  }

  Widget _buildReminderCard(Reminder reminder) {
    final isRecurring = reminder.type == ReminderType.recurring;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSizes.paddingMedium),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
        onTap: () => _editReminder(reminder),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingMedium),
          child: Row(
            children: [
              // Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isRecurring
                      ? Colors.blue.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isRecurring ? Icons.repeat : Icons.notifications_active,
                  color: isRecurring ? Colors.blue : Colors.orange,
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
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reminder.formattedSchedule,
                      style: AppTextStyles.caption.copyWith(
                        color: isRecurring ? Colors.blue : Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Next: ${reminder.formattedNextTrigger}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _deleteReminder(reminder),
              ),
            ],
          ),
        ),
      ),
    );
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
      title: const Text('Edit Reminder'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'What to remind you about',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            if (isRecurring) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _intervalController,
                decoration: const InputDecoration(
                  labelText: 'Interval (minutes)',
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
    );

    if (time != null) {
      setState(() => _scheduledTime = time);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Reminder'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'What to remind you about',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            const Text('Type:'),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<ReminderType>(
                    title: const Text('Recurring'),
                    value: ReminderType.recurring,
                    groupValue: _type,
                    onChanged: (value) => setState(() => _type = value!),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                Expanded(
                  child: RadioListTile<ReminderType>(
                    title: const Text('One-time'),
                    value: ReminderType.oneTime,
                    groupValue: _type,
                    onChanged: (value) => setState(() => _type = value!),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_type == ReminderType.recurring)
              TextField(
                controller: _intervalController,
                decoration: const InputDecoration(
                  labelText: 'Interval (minutes)',
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
                ),
                trailing: const Icon(Icons.access_time),
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

              // If time has passed, schedule for tomorrow
              if (scheduledDateTime.isBefore(now)) {
                scheduledDateTime = scheduledDateTime.add(const Duration(days: 1));
              }

              Navigator.pop(context, {
                'message': message,
                'type': _type,
                'intervalMinutes': null,
                'scheduledTime': scheduledDateTime,
              });
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
