import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_show_when_locked/flutter_show_when_locked.dart';
import '../models/reminder_model.dart';
import '../services/reminder_service.dart';
import '../widgets/slide_to_stop.dart';

class AlarmScreen extends StatefulWidget {
  final String message;
  final int alarmId;
  final String? reminderId;

  const AlarmScreen({
    super.key,
    required this.message,
    required this.alarmId,
    this.reminderId,
  });

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> with WidgetsBindingObserver {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  final FlutterShowWhenLocked _showWhenLocked = FlutterShowWhenLocked();
  final ReminderService _reminderService = ReminderService();
  bool _isStopped = false;
  Reminder? _reminder;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    print('[AlarmScreen] initState - alarmId: ${widget.alarmId}, message: ${widget.message}, reminderId: ${widget.reminderId}');

    // Enable showing over lock screen
    _enableShowWhenLocked();

    // Load reminder details if we have the ID
    _loadReminder();

    // Delay immersive mode slightly to ensure screen is visible first
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        // Make the screen full-screen and keep screen on
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });

    _startAlarm();
  }

  Future<void> _loadReminder() async {
    if (widget.reminderId != null) {
      _reminder = await _reminderService.getReminderById(widget.reminderId!);
      print('[AlarmScreen] Loaded reminder: ${_reminder?.message}, isDurationBased: ${_reminder?.isDurationBased}, type: ${_reminder?.type}');
      // Rebuild UI to show recurring status
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _enableShowWhenLocked() async {
    try {
      print('[AlarmScreen] Enabling show when locked...');
      await _showWhenLocked.show();
      print('[AlarmScreen] Show when locked enabled');
    } catch (e) {
      print('[AlarmScreen] Error enabling show when locked: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopAlarm();
    _disableShowWhenLocked();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _disableShowWhenLocked() async {
    try {
      await _showWhenLocked.hide();
      print('[AlarmScreen] Show when locked disabled');
    } catch (e) {
      print('[AlarmScreen] Error disabling show when locked: $e');
    }
  }

  Future<void> _startAlarm() async {
    // First speak the TTS message once
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.speak('Reminder: ${widget.message}');

    // Then start looping the alarm sound
    await _playAlarmSound();
  }

  Future<void> _playAlarmSound() async {
    if (_isStopped) return;

    try {
      // Set player to loop
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);

      // Try to play the alarm sound from assets
      print('[AlarmScreen] Attempting to play alarm sound...');
      await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
      print('[AlarmScreen] Alarm sound playing');
    } catch (e) {
      print('[AlarmScreen] Error playing alarm sound: $e');
      print('[AlarmScreen] Note: Add alarm.mp3 to assets/sounds/ for alarm sound');
      // Fallback: If no alarm sound, the UI and TTS still work
    }
  }

  Future<void> _stopAlarm() async {
    if (_isStopped) return;
    _isStopped = true;

    // Stop audio
    await _audioPlayer.stop();
    await _audioPlayer.dispose();

    // Stop TTS
    await _tts.stop();

    // Clear the active alarm UI data from SharedPreferences
    // Note: Don't remove alarm_$alarmId here - it's needed for recurring logic
    // and will be cleaned up by markReminderAsTriggered or makeReminderRecurring
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_alarm_id');
    await prefs.remove('active_alarm_message');
    await prefs.remove('active_alarm_timestamp');
    await prefs.remove('active_alarm_reminder_id');
  }

  void _onSlideComplete() async {
    await _stopAlarm();

    if (!mounted) return;

    // Check if we should show the recurring dialog
    // Only show for duration-based reminders that are NOT already recurring
    final reminder = _reminder;
    if (reminder != null &&
        reminder.isDurationBased &&
        reminder.type != ReminderType.recurring) {
      print('[AlarmScreen] Showing recurring prompt for duration-based reminder');
      final result = await _showRecurringDialog();
      await _handleRecurringChoice(result, reminder);
    } else {
      // Not duration-based or already recurring - just mark as triggered for one-time
      if (reminder != null && reminder.type == ReminderType.oneTime) {
        await _reminderService.markReminderAsTriggered(reminder.id);
      }
      // For recurring reminders, don't mark as triggered - let it continue recurring
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Stop recurring reminder permanently and move to past reminders
  void _onStopRecurring() async {
    await _stopAlarm();

    if (!mounted) return;

    final reminder = _reminder;
    if (reminder != null) {
      print('[AlarmScreen] Stopping recurring reminder permanently: ${reminder.id}');
      await _reminderService.markReminderAsTriggered(reminder.id);
      print('[AlarmScreen] Recurring reminder stopped and moved to past reminders');
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<String?> _showRecurringDialog() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RecurringDialog(
        message: widget.message,
        originalInterval: _reminder?.intervalMinutes,
      ),
    );
  }

  Future<void> _handleRecurringChoice(String? choice, Reminder reminder) async {
    print('[AlarmScreen] Handling recurring choice: $choice for reminder: ${reminder.id}');

    if (choice == null || choice == 'no') {
      // No recurring - mark as triggered and move to past
      await _reminderService.markReminderAsTriggered(reminder.id);
      print('[AlarmScreen] Reminder marked as triggered (no recurring)');
    } else if (choice == 'yes') {
      // Recurring at same interval
      final result = await _reminderService.makeReminderRecurring(reminder.id);
      print('[AlarmScreen] Reminder made recurring at same interval: ${result?.intervalMinutes} minutes, next: ${result?.nextTrigger}');
    } else if (choice == 'daily') {
      // Recurring daily (1440 minutes)
      final result = await _reminderService.makeReminderRecurring(reminder.id, intervalMinutes: 1440);
      print('[AlarmScreen] Reminder made recurring daily, next: ${result?.nextTrigger}');
    } else if (choice.startsWith('custom:')) {
      // Custom interval
      final minutes = int.tryParse(choice.substring(7));
      if (minutes != null && minutes > 0) {
        final result = await _reminderService.makeReminderRecurring(reminder.id, intervalMinutes: minutes);
        print('[AlarmScreen] Reminder made recurring every $minutes minutes, next: ${result?.nextTrigger}');
      } else {
        // Invalid custom value - treat as no
        await _reminderService.markReminderAsTriggered(reminder.id);
      }
    }
  }

  /// Check if the reminder is recurring
  bool get _isRecurring => _reminder?.type == ReminderType.recurring;

  @override
  Widget build(BuildContext context) {
    print('[AlarmScreen] build - rendering alarm UI, isRecurring: $_isRecurring');
    return PopScope(
      canPop: false, // Prevent back button from closing
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1a237e), // Deep indigo
                Color(0xFF0d47a1), // Deep blue
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Alarm icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isRecurring ? Icons.repeat : Icons.alarm,
                    size: 60,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 40),

                // Title - show RECURRING REMINDER for recurring alarms
                Text(
                  _isRecurring ? 'RECURRING REMINDER' : 'REMINDER',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 20),

                // Message
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // Show interval info for recurring reminders
                if (_isRecurring && _reminder?.intervalMinutes != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Repeats every ${_formatInterval(_reminder!.intervalMinutes!)}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],

                const Spacer(flex: 3),

                // Slide to stop (snooze for recurring, dismiss for one-time)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: SlideToStop(
                    onSlideComplete: _onSlideComplete,
                    label: _isRecurring ? 'Slide to snooze' : 'Slide to stop',
                  ),
                ),

                // Stop Recurring button - only show for recurring reminders
                if (_isRecurring) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _onStopRecurring,
                        icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
                        label: const Text(
                          'Stop Recurring',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.white.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Format interval in human readable form
  String _formatInterval(int minutes) {
    if (minutes >= 1440) {
      final days = minutes ~/ 1440;
      return days == 1 ? '1 day' : '$days days';
    } else if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      if (mins == 0) {
        return hours == 1 ? '1 hour' : '$hours hours';
      }
      return '$hours hr $mins min';
    } else {
      return minutes == 1 ? '1 minute' : '$minutes minutes';
    }
  }
}

/// Dialog for choosing recurring options
class _RecurringDialog extends StatefulWidget {
  final String message;
  final int? originalInterval;

  const _RecurringDialog({
    required this.message,
    this.originalInterval,
  });

  @override
  State<_RecurringDialog> createState() => _RecurringDialogState();
}

class _RecurringDialogState extends State<_RecurringDialog> {
  bool _showCustomPicker = false;
  int _customHours = 0;
  int _customMinutes = 30;

  String get _originalIntervalText {
    if (widget.originalInterval == null) return 'same interval';
    final hours = widget.originalInterval! ~/ 60;
    final mins = widget.originalInterval! % 60;
    if (hours > 0 && mins > 0) {
      return '$hours hour${hours > 1 ? 's' : ''} $mins min${mins > 1 ? 's' : ''}';
    } else if (hours > 0) {
      return '$hours hour${hours > 1 ? 's' : ''}';
    } else {
      return '$mins minute${mins > 1 ? 's' : ''}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Make this recurring?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Would you like to repeat "${widget.message}" as a recurring reminder?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),

            if (!_showCustomPicker) ...[
              // Main options
              _buildOptionButton(
                context,
                icon: Icons.repeat,
                label: 'Yes',
                subtitle: 'Repeat every $_originalIntervalText',
                onTap: () => Navigator.pop(context, 'yes'),
              ),
              const SizedBox(height: 8),
              _buildOptionButton(
                context,
                icon: Icons.close,
                label: 'No',
                subtitle: 'Don\'t repeat',
                onTap: () => Navigator.pop(context, 'no'),
              ),
              const SizedBox(height: 8),
              _buildOptionButton(
                context,
                icon: Icons.today,
                label: 'Daily',
                subtitle: 'Repeat every 24 hours',
                onTap: () => Navigator.pop(context, 'daily'),
              ),
              const SizedBox(height: 8),
              _buildOptionButton(
                context,
                icon: Icons.tune,
                label: 'Custom',
                subtitle: 'Set a custom interval',
                onTap: () {
                  setState(() => _showCustomPicker = true);
                },
              ),
            ] else ...[
              // Custom interval picker
              const Text(
                'Set custom interval:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  // Hours picker
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Hours', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListWheelScrollView.useDelegate(
                            itemExtent: 40,
                            physics: const FixedExtentScrollPhysics(),
                            onSelectedItemChanged: (index) {
                              setState(() => _customHours = index);
                            },
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: 24,
                              builder: (context, index) => Center(
                                child: Text(
                                  '$index',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: index == _customHours ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Minutes picker
                  Expanded(
                    child: Column(
                      children: [
                        const Text('Minutes', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListWheelScrollView.useDelegate(
                            itemExtent: 40,
                            physics: const FixedExtentScrollPhysics(),
                            controller: FixedExtentScrollController(initialItem: 30),
                            onSelectedItemChanged: (index) {
                              setState(() => _customMinutes = index);
                            },
                            childDelegate: ListWheelChildBuilderDelegate(
                              childCount: 60,
                              builder: (context, index) => Center(
                                child: Text(
                                  '$index',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: index == _customMinutes ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Every ${_customHours > 0 ? "$_customHours hour${_customHours > 1 ? "s" : ""} " : ""}$_customMinutes minute${_customMinutes > 1 ? "s" : ""}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => _showCustomPicker = false);
                    },
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final totalMinutes = _customHours * 60 + _customMinutes;
                      if (totalMinutes > 0) {
                        Navigator.pop(context, 'custom:$totalMinutes');
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please select a valid interval')),
                        );
                      }
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
