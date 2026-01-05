import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_show_when_locked/flutter_show_when_locked.dart';
import '../widgets/slide_to_stop.dart';

class AlarmScreen extends StatefulWidget {
  final String message;
  final int alarmId;

  const AlarmScreen({
    super.key,
    required this.message,
    required this.alarmId,
  });

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> with WidgetsBindingObserver {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FlutterTts _tts = FlutterTts();
  final FlutterShowWhenLocked _showWhenLocked = FlutterShowWhenLocked();
  bool _isStopped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    print('[AlarmScreen] initState - alarmId: ${widget.alarmId}, message: ${widget.message}');

    // Enable showing over lock screen
    _enableShowWhenLocked();

    // Delay immersive mode slightly to ensure screen is visible first
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        // Make the screen full-screen and keep screen on
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });

    _startAlarm();
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

    // Clear the active alarm from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_alarm_id');
    await prefs.remove('active_alarm_message');
    await prefs.remove('active_alarm_timestamp');
    await prefs.remove('alarm_${widget.alarmId}');
  }

  void _onSlideComplete() async {
    await _stopAlarm();

    if (mounted) {
      // Pop this screen and go back
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    print('[AlarmScreen] build - rendering alarm UI');
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
                  child: const Icon(
                    Icons.alarm,
                    size: 60,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 40),

                // Title
                const Text(
                  'REMINDER',
                  style: TextStyle(
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

                const Spacer(flex: 3),

                // Slide to stop
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: SlideToStop(
                    onSlideComplete: _onSlideComplete,
                    label: 'Slide to stop',
                  ),
                ),

                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
