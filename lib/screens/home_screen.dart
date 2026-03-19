import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/local_db_service.dart';
import '../services/embedding_service.dart';
import '../services/llm_service.dart';
import '../services/reminder_service.dart';
import '../services/subscription_service.dart';
import '../services/wake_word_service.dart';
import '../models/user_model.dart';
import '../models/memory_model.dart';
import '../models/reminder_model.dart';
import '../utils/constants.dart';
import '../widgets/confirmation_dialog.dart';
import '../widgets/starfield_background.dart';
import '../widgets/glass_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'all_memories_screen.dart';
import 'reminders_screen.dart';
import 'upgrade_screen.dart';
import 'wake_word_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  final ReminderService _reminderService = ReminderService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  final WakeWordService _wakeWordService = WakeWordService();

  // Speech recognition
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isListening = false;
  bool _speechInitialized = false;
  String _transcribedText = '';
  String _statusText = 'Tap to speak';
  bool _isProcessing = false;
  bool _hasProcessedCurrentInput = false; // Prevents duplicate processing
  bool _pendingMicFromNotification = false; // Flag to start listening when app resumes
  bool _listeningFromNotification = false; // Flag to suppress TTS error when from notification

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupNotificationService();
    _initializeReminderService();
    _initializeSubscriptionService();
    _initSpeech();
    _initTts();
    _initWakeWordService();
  }

  Future<void> _initializeSubscriptionService() async {
    await _subscriptionService.initialize();
  }

  Future<void> _initSpeech() async {
    _speechInitialized = await _speech.initialize(
      onStatus: (status) {
        print('[HomeScreen] Speech status: $status');
        // DON'T process on notListening - wait for finalResult in onResult
        // This prevents processing incomplete partial results
        if (status == 'notListening') {
          // Speech stopped but we haven't received finalResult yet
          // Wait longer (1.5s) for the final result to arrive
          // This gives time for the speech recognizer to send the complete result
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (_isListening && !_hasProcessedCurrentInput && _transcribedText.isNotEmpty) {
              // Only process if the text looks complete (doesn't end with incomplete words)
              final text = _transcribedText.trim().toLowerCase();
              final incompleteEndings = ['every', 'in', 'at', 'after', 'to', 'the', 'my', 'a', 'an'];
              final lastWord = text.split(' ').last;

              if (incompleteEndings.contains(lastWord)) {
                print('[HomeScreen] Text appears incomplete (ends with "$lastWord"), waiting more...');
                // Wait another second for completion
                Future.delayed(const Duration(milliseconds: 1000), () {
                  if (_isListening && !_hasProcessedCurrentInput && _transcribedText.isNotEmpty) {
                    print('[HomeScreen] Processing after extended delay');
                    _processVoiceInput();
                  }
                });
              } else {
                print('[HomeScreen] Processing after notListening delay (finalResult may have been missed)');
                _processVoiceInput();
              }
            }
          });
        } else if (status == 'done') {
          // Speech completely finished - reset UI if we haven't processed
          if (_isListening && !_hasProcessedCurrentInput) {
            setState(() {
              _isListening = false;
              _statusText = 'Tap to speak';
              _listeningFromNotification = false;
            });
          }
        }
      },
      onError: (error) {
        print('[HomeScreen] Speech error: $error');
        final wasFromNotification = _listeningFromNotification;
        setState(() {
          _isListening = false;
          _statusText = 'Tap to speak';
          _transcribedText = '';
          _listeningFromNotification = false;
        });
        if (!wasFromNotification) {
          _speak('Sorry, I couldn\'t hear you. Please try again.');
        }
        _wakeWordService.resume();
      },
    );
    print('[HomeScreen] Speech initialized: $_speechInitialized');
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _initWakeWordService() async {
    _wakeWordService.onWakeWordDetected = _onWakeWordDetected;
    await _wakeWordService.initialize();
    if (mounted) setState(() {});

    // Show enrollment screen if not yet enrolled
    if (_wakeWordService.isInitialized && !_wakeWordService.isEnrolled) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) _showEnrollmentScreen();
    }
  }

  Future<void> _showEnrollmentScreen() async {
    await _wakeWordService.pause();
    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const WakeWordSetupScreen(),
      ),
    );

    if (mounted) {
      if (result == true) {
        await _wakeWordService.resume();
      } else {
        await _wakeWordService.resume();
      }
      setState(() {});
    }
  }

  Future<void> _onWakeWordDetected() async {
    if (!mounted || _isListening || _isProcessing) return;
    print('[HomeScreen] Wake word "Hey Neurix" detected!');

    // Get user's first name
    final user = Provider.of<UserModel?>(context, listen: false);
    final name = user?.displayName?.split(' ').first ?? 'there';

    // Randomized greeting
    final greetings = [
      'Yes $name?',
      'Hello $name, how can I help you?',
      'Uh-huh?',
      'Hey $name, what do you need?',
      'I\'m listening, $name',
      'What\'s up, $name?',
      'Go ahead, $name',
    ];
    final greeting = greetings[Random().nextInt(greetings.length)];

    // Show greeting in status text
    setState(() {
      _statusText = greeting;
    });

    // Speak greeting and wait for it to finish (can't overlap TTS + mic)
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(greeting);
    await _tts.awaitSpeakCompletion(false);

    // Start listening immediately after TTS (no extra delay)
    if (mounted && !_isListening && !_isProcessing) {
      _startListening();
    }
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  Future<void> _startListening() async {
    print('[HomeScreen] ========================================');
    print('[HomeScreen] === STARTING LISTENING ===');
    print('[HomeScreen] ========================================');

    // Pause wake word service if active (only one speech recognizer at a time)
    if (_wakeWordService.isEnabled && !_wakeWordService.isListening) {
      // Already paused (e.g. from wake word detection)
    } else if (_wakeWordService.isEnabled) {
      await _wakeWordService.pause();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (!_speechInitialized) {
      print('[HomeScreen] Speech not initialized, initializing...');
      await _initSpeech();
    }

    if (!_speechInitialized) {
      print('[HomeScreen] Speech recognition not available!');
      _speak('Speech recognition is not available');
      return;
    }

    print('[HomeScreen] Starting speech recognition...');
    setState(() {
      _isListening = true;
      _transcribedText = '';
      _statusText = 'Listening...';
      _hasProcessedCurrentInput = false; // Reset for new input
      _listeningFromNotification = false; // Ensure flag is false for on-screen mic
    });

    await _speech.listen(
      onResult: (result) {
        print('[HomeScreen] Speech result - words: "${result.recognizedWords}", final: ${result.finalResult}');
        setState(() {
          _transcribedText = result.recognizedWords;
          if (_transcribedText.isNotEmpty) {
            _statusText = _transcribedText;
          }
        });

        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          print('[HomeScreen] Final result received, stopping and processing...');
          _speech.stop();
          _processVoiceInput();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  Future<void> _stopListening() async {
    print('[HomeScreen] === STOPPING LISTENING ===');
    print('[HomeScreen] Transcribed text so far: "$_transcribedText"');
    await _speech.stop();
    setState(() {
      _isListening = false;
      if (_transcribedText.isEmpty) {
        _statusText = 'Tap to speak';
      }
    });
    _wakeWordService.resume();
  }

  /// ===========================================
  /// MAIN VOICE INPUT PROCESSING FLOW
  /// ===========================================
  /// 1. LLM Call 1: Detect intent (save/search/reminder/cancel_reminder/unclear)
  /// 2. Route to appropriate handler based on intent
  /// 3. Speak response and reset UI
  Future<void> _processVoiceInput() async {
    if (_transcribedText.isEmpty) {
      _wakeWordService.resume();
      return;
    }

    // Prevent duplicate processing - both onStatus and onResult can trigger this
    if (_hasProcessedCurrentInput) {
      print('[FLOW] Already processed this input, skipping duplicate call');
      return;
    }
    _hasProcessedCurrentInput = true;

    print('[FLOW] ========================================');
    print('[FLOW] User said: "$_transcribedText"');
    print('[FLOW] ========================================');

    setState(() {
      _isListening = false;
      _isProcessing = true;
      _statusText = 'Processing...';
    });

    try {
      // STEP 1: Detect intent using LLM
      final llmService = LLMService();
      final intent = await llmService.detectIntent(_transcribedText);
      print('[FLOW] Intent detected: "$intent"');

      String response;

      // STEP 2: Route based on intent (simple if-else)
      if (intent == 'save') {
        // Add Memory: Show confirmation dialog first
        print('[FLOW] -> SAVE MEMORY (showing confirmation)');
        setState(() { _isProcessing = false; });

        final confirmed = await showConfirmationDialog(
          context: context,
          intent: 'save',
          transcribedText: _transcribedText,
        );

        if (confirmed) {
          print('[FLOW] User confirmed save');
          setState(() { _isProcessing = true; _statusText = 'Saving...'; });
          response = await _handleAddMemory(_transcribedText);
        } else {
          print('[FLOW] User cancelled save');
          response = 'Okay, cancelled.';
          await _speak(response);
          setState(() { _statusText = 'Tap to speak'; _transcribedText = ''; });
          _wakeWordService.resume();
          return;
        }
      } else if (intent == 'search') {
        // Search Memory: No confirmation needed - execute immediately
        print('[FLOW] -> SEARCH MEMORY');
        response = await _handleSearchMemory(_transcribedText);
      } else if (intent == 'reminder') {
        // Save Reminder: Show confirmation dialog first
        print('[FLOW] -> SAVE REMINDER (showing confirmation)');
        setState(() { _isProcessing = false; });

        final confirmed = await showConfirmationDialog(
          context: context,
          intent: 'reminder',
          transcribedText: _transcribedText,
        );

        if (confirmed) {
          print('[FLOW] User confirmed reminder');
          setState(() { _isProcessing = true; _statusText = 'Setting reminder...'; });
          response = await _handleCreateReminder(_transcribedText);
        } else {
          print('[FLOW] User cancelled reminder');
          response = 'Okay, cancelled.';
          await _speak(response);
          setState(() { _statusText = 'Tap to speak'; _transcribedText = ''; });
          _wakeWordService.resume();
          return;
        }
      } else if (intent == 'cancel_reminder') {
        // Delete Reminder: No confirmation needed - execute immediately
        print('[FLOW] -> DELETE REMINDER');
        response = await _handleCancelReminder(_transcribedText);
      } else {
        // Unclear: Inform user and go back to wake word detection
        print('[FLOW] -> UNCLEAR, returning to wake word mode');
        response = "Sorry, that's not something I can help with. I can save memories, search them, or set reminders.";
        setState(() { _statusText = response; _isProcessing = false; });
        await _speak(response);
        setState(() { _statusText = 'Tap to speak'; _transcribedText = ''; });
        _wakeWordService.resume();
        return;
      }

      print('[FLOW] Response: "$response"');
      print('[FLOW] ========================================');

      // STEP 3: Show response and speak
      setState(() { _statusText = response; _isProcessing = false; });
      await _speak(response);

      // Reset UI after speaking
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() { _statusText = 'Tap to speak'; _transcribedText = ''; });
      }
      _wakeWordService.resume();
    } catch (e) {
      print('[FLOW] ERROR: $e');
      setState(() { _statusText = 'Something went wrong'; _isProcessing = false; });
      await _speak('Sorry, something went wrong.');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() { _statusText = 'Tap to speak'; });
      _wakeWordService.resume();
    }
  }

  Future<void> _initializeReminderService() async {
    await _reminderService.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Don't cancel notifications on dispose - they should persist
    // until the app is fully terminated (handled in didChangeAppLifecycleState)
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground - ensure notification is visible
        _notificationService.showVoiceNotification(
          title: 'Neurix',
          body: _wakeWordService.isEnabled ? '"Hey Neurix" is active' : 'Tap to speak',
        );

        // Resume wake word listening when app comes to foreground
        if (_wakeWordService.isEnabled && !_isListening && !_isProcessing) {
          _wakeWordService.resume();
        }

        // Check if we have a pending mic press from notification
        if (_pendingMicFromNotification) {
          print('[HomeScreen] App resumed with pending mic press, starting listening');
          _pendingMicFromNotification = false;
          // Longer delay to ensure audio system is fully ready after background-to-foreground transition
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted && !_isListening && !_isProcessing) {
              _startListeningFromNotification();
            }
          });
        }
        break;
      case AppLifecycleState.paused:
        // App went to background - pause wake word to save battery
        _wakeWordService.pause();
        // Re-show notification
        _notificationService.showVoiceNotification(
          title: 'Neurix',
          body: _wakeWordService.isEnabled ? '"Hey Neurix" is active' : 'Tap to speak',
        );
        break;
      case AppLifecycleState.detached:
        // App is being terminated - stop everything
        _wakeWordService.stop();
        _notificationService.cancelAllNotifications();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // No action needed for these states
        break;
    }
  }

  Future<void> _setupNotificationService() async {
    // Small delay to ensure UI is ready
    await Future.delayed(const Duration(milliseconds: 500));

    // Request notification permission
    final hasPermission = await _notificationService.requestPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please grant notification permission for voice control'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Set up mic button handler - triggers speech recognition when notification mic is pressed
    _notificationService.onMicPressed = _handleNotificationMicPress;

    // Show the persistent voice control notification
    await _notificationService.showVoiceNotification(
      title: 'Neurix',
      body: _wakeWordService.isEnabled ? '"Hey Neurix" is active' : 'Tap to speak',
    );
    print('[HomeScreen] Notification service initialized');
  }

  /// Handle mic button press from notification - triggers speech recognition
  void _handleNotificationMicPress() {
    print('[NOTIFICATION] Mic button pressed from notification');
    // Set flag to start listening when app is fully resumed
    // This is needed because the app may still be paused when this is called
    _pendingMicFromNotification = true;

    // If app is already in foreground and active, start listening immediately
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      print('[NOTIFICATION] App already resumed, starting listening');
      _pendingMicFromNotification = false;
      if (!_isListening && !_isProcessing) {
        // Use small delay even when already resumed to ensure audio is ready
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && !_isListening && !_isProcessing) {
            _startListeningFromNotification();
          }
        });
      }
    } else {
      print('[NOTIFICATION] App not resumed yet, will start listening on resume');
    }
  }

  /// Start listening from notification - silent error handling (no TTS on error)
  Future<void> _startListeningFromNotification() async {
    print('[HomeScreen] ========================================');
    print('[HomeScreen] === STARTING LISTENING (from notification) ===');
    print('[HomeScreen] ========================================');

    // Pause wake word service if active
    if (_wakeWordService.isEnabled) {
      await _wakeWordService.pause();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (!_speechInitialized) {
      print('[HomeScreen] Speech not initialized, initializing...');
      await _initSpeech();
    }

    if (!_speechInitialized) {
      print('[HomeScreen] Speech recognition not available!');
      // Don't speak error - just reset state silently
      return;
    }

    print('[HomeScreen] Starting speech recognition...');
    setState(() {
      _isListening = true;
      _transcribedText = '';
      _statusText = 'Listening...';
      _hasProcessedCurrentInput = false;
      _listeningFromNotification = true; // Set flag to suppress TTS error
    });

    await _speech.listen(
      onResult: (result) {
        print('[HomeScreen] Speech result - words: "${result.recognizedWords}", final: ${result.finalResult}');
        setState(() {
          _transcribedText = result.recognizedWords;
          if (_transcribedText.isNotEmpty) {
            _statusText = _transcribedText;
          }
        });

        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          print('[HomeScreen] Final result received, stopping and processing...');
          _listeningFromNotification = false; // Reset flag
          _speech.stop();
          _processVoiceInput();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  /// SAVE MEMORY: Save raw text + embedding to database (No extra LLM call)
  Future<String> _handleAddMemory(String content) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.uid ?? 'anonymous';

      final localDbService = LocalDbService();

      // Check subscription limits
      final currentCount = await localDbService.getMemoryCount(userId);
      if (!_subscriptionService.canAddMemory(currentCount)) {
        print('[SAVE] Memory limit reached: $currentCount/${SubscriptionLimits.freeMemories}');
        // Show upgrade screen
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const UpgradeScreen(limitReachedType: 'memory'),
            ),
          );
        }
        return 'You\'ve reached the free memory limit. Upgrade to Pro for unlimited memories!';
      }

      final embeddingService = EmbeddingService();
      final llmService = LLMService();

      // Clean the content (remove "remember", "save", etc.)
      final cleanContent = llmService.extractMemoryContent(content);
      print('[SAVE] Content: "$cleanContent"');

      // Generate embedding for similarity search
      final embedding = await embeddingService.generateEmbedding(cleanContent, isQuery: false);
      print('[SAVE] Embedding generated: ${embedding?.length ?? 0} dimensions');

      final memory = Memory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: cleanContent,
        createdAt: DateTime.now(),
        userId: userId,
        embedding: embedding,
      );

      final success = await localDbService.saveMemory(memory);
      print('[SAVE] Saved to DB: $success');

      return success ? 'Got it! I\'ll remember that.' : 'Sorry, I couldn\'t save that memory.';
    } catch (e) {
      print('[SAVE] Error: $e');
      return 'Sorry, there was an error saving the memory.';
    }
  }

  /// SEARCH MEMORY: Similarity search + LLM response (LLM Call 2)
  Future<String> _handleSearchMemory(String query) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.uid ?? 'anonymous';

      final localDbService = LocalDbService();
      final embeddingService = EmbeddingService();
      final llmService = LLMService();

      // Generate query embedding for similarity search
      final queryEmbedding = await embeddingService.generateEmbedding(query, isQuery: true);
      print('[SEARCH] Query embedding: ${queryEmbedding?.length ?? 0} dimensions');

      // Semantic search
      List<Memory> memories = await localDbService.semanticSearchMemories(
        userId,
        queryEmbedding,
        topK: 5,
        similarityThreshold: 0.2,
      );
      print('[SEARCH] Found ${memories.length} memories via semantic search');

      // Fallback to keyword search if no results
      if (memories.isEmpty) {
        memories = await localDbService.searchMemories(userId, query);
        print('[SEARCH] Found ${memories.length} memories via keyword search');
      }

      if (memories.isEmpty) {
        return 'I don\'t have any memories about that.';
      }

      // LLM Call 2: Generate contextual response from memories
      final response = await llmService.generateContextualResponse(query, memories);
      return response;
    } catch (e) {
      print('[SEARCH] Error: $e');
      return 'Sorry, there was an error searching your memories.';
    }
  }

  /// SAVE REMINDER: LLM parses recurring/one-time + time + save to DB (LLM Call 3)
  Future<String> _handleCreateReminder(String text) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.uid ?? 'anonymous';

      final localDbService = LocalDbService();

      // Check subscription limits
      final currentCount = await localDbService.getReminderCount(userId);
      if (!_subscriptionService.canAddReminder(currentCount)) {
        print('[REMINDER] Reminder limit reached: $currentCount/${SubscriptionLimits.freeReminders}');
        // Show upgrade screen
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const UpgradeScreen(limitReachedType: 'reminder'),
            ),
          );
        }
        return 'You\'ve reached the free reminder limit. Upgrade to Pro for unlimited reminders!';
      }

      // LLM Call 3: Parse reminder details
      final llmService = LLMService();
      var parsed = await llmService.parseReminderFromVoice(text);

      // Fallback to regex-based parsing if LLM fails
      if (parsed == null) {
        print('[REMINDER] LLM parsing failed, using regex fallback');
        parsed = ReminderService.parseReminderFromVoice(text);
      }

      if (parsed == null) {
        return 'I couldn\'t understand the reminder. Try "remind me to do something in 30 minutes".';
      }

      print('[REMINDER] Type: ${parsed['type']}, Message: ${parsed['message']}');
      print('[REMINDER] Interval: ${parsed['intervalMinutes']}, Time: ${parsed['scheduledTime']}');

      // Convert type string to enum
      ReminderType reminderType = (parsed['type'] == 'recurring' || parsed['type'] == ReminderType.recurring)
          ? ReminderType.recurring
          : ReminderType.oneTime;

      final reminder = await _reminderService.createReminder(
        userId: userId,
        message: parsed['message'] as String,
        type: reminderType,
        intervalMinutes: parsed['intervalMinutes'] as int?,
        scheduledTime: parsed['scheduledTime'] as DateTime?,
        isDurationBased: parsed['isDurationBased'] as bool?,
      );

      if (reminder == null) {
        return 'Sorry, I couldn\'t create the reminder.';
      }

      print('[REMINDER] Created: ${reminder.id}');
      return 'I\'ll remind you to ${reminder.message.toLowerCase()} ${reminder.formattedSchedule.toLowerCase()}.';
    } catch (e) {
      print('[REMINDER] Error: $e');
      return 'Sorry, there was an error creating the reminder.';
    }
  }

  /// DELETE REMINDER: LLM parses which reminder + delete from DB (LLM Call 4)
  Future<String> _handleCancelReminder(String text) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.uid ?? 'anonymous';

      // LLM Call 4: Parse which reminder to cancel
      final llmService = LLMService();
      var searchText = await llmService.parseCancelReminderRequest(text);
      print('[DELETE] LLM parsed: "$searchText"');

      // Fallback to regex if LLM fails
      if (searchText == null) {
        print('[DELETE] LLM failed, using regex fallback');
        searchText = ReminderService.parseCancelCommand(text);
        if (searchText == '__ALL__') searchText = 'all';
        print('[DELETE] Regex parsed: "$searchText"');
      }

      if (searchText == null) {
        return 'I couldn\'t understand which reminder to cancel.';
      }

      if (searchText == 'all') {
        // Cancel all reminders
        final success = await _reminderService.cancelAllReminders(userId);
        print('[DELETE] Cancel all: $success');
        return success ? 'All your reminders have been cancelled.' : 'Sorry, I couldn\'t cancel your reminders.';
      } else {
        // Cancel specific reminder
        final success = await _reminderService.cancelReminderByMessage(userId, searchText);
        print('[DELETE] Cancel "$searchText": $success');
        return success ? 'I\'ve cancelled the $searchText reminder.' : 'I couldn\'t find a reminder matching "$searchText".';
      }
    } catch (e) {
      print('[DELETE] Error: $e');
      return 'Sorry, there was an error cancelling the reminder.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final UserModel? user = Provider.of<UserModel?>(context);
    final userId = user?.uid ?? 'anonymous';

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon/neurixLogo_white.png',
              width: 28,
              height: 28,
            ),
            const SizedBox(width: 8),
            const Text(
              'Neurix',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppColors.textSecondary),
            onPressed: () async {
              await authService.signOut();
            },
          ),
        ],
      ),
      body: StarfieldBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.paddingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User Profile Card
                GlassCard(
                  onTap: () => _showProfileSheet(user),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withOpacity(0.3),
                              AppColors.primaryLight.withOpacity(0.15),
                            ],
                          ),
                        ),
                        child: user?.photoUrl != null
                            ? ClipOval(
                                child: Image.network(
                                  user!.photoUrl!,
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(
                                    Icons.person_outline,
                                    size: 25,
                                    color: AppColors.primaryLight,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.person_outline,
                                size: 25,
                                color: AppColors.primaryLight,
                              ),
                      ),
                      const SizedBox(width: AppSizes.paddingMedium),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? 'User',
                              style: AppTextStyles.subheading,
                            ),
                            if (user?.email != null)
                              Text(
                                user!.email,
                                style: AppTextStyles.caption.copyWith(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: AppColors.textHint,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.paddingLarge * 1.5),

                // Big Mic Button
                Center(
                  child: GestureDetector(
                    onTap: _isProcessing
                        ? null
                        : (_isListening ? _stopListening : _startListening),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: _isListening ? 150 : 130,
                      height: _isListening ? 150 : 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: _isListening
                              ? [
                                  const Color(0xFFEF4444),
                                  const Color(0xFFDC2626),
                                ]
                              : _isProcessing
                                  ? [
                                      AppColors.warning,
                                      const Color(0xFFD97706),
                                    ]
                                  : [
                                      AppColors.primaryLight,
                                      AppColors.primary,
                                    ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening
                                    ? const Color(0xFFEF4444)
                                    : _isProcessing
                                        ? AppColors.warning
                                        : AppColors.primary)
                                .withOpacity(0.4),
                            blurRadius: _isListening ? 40 : 25,
                            spreadRadius: _isListening ? 8 : 2,
                          ),
                          BoxShadow(
                            color: (_isListening
                                    ? const Color(0xFFEF4444)
                                    : _isProcessing
                                        ? AppColors.warning
                                        : AppColors.primary)
                                .withOpacity(0.15),
                            blurRadius: 60,
                            spreadRadius: 15,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening
                            ? Icons.stop_rounded
                            : _isProcessing
                                ? Icons.hourglass_top_rounded
                                : Icons.mic_rounded,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.paddingMedium),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.paddingMedium,
                      vertical: AppSizes.paddingSmall,
                    ),
                    decoration: BoxDecoration(
                      color: _isListening
                          ? const Color(0xFFEF4444).withOpacity(0.12)
                          : _isProcessing
                              ? AppColors.warning.withOpacity(0.12)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: (_isListening || _isProcessing)
                          ? Border.all(
                              color: (_isListening
                                      ? const Color(0xFFEF4444)
                                      : AppColors.warning)
                                  .withOpacity(0.2),
                            )
                          : null,
                    ),
                    child: Text(
                      _statusText,
                      style: AppTextStyles.body.copyWith(
                        color: _isListening
                            ? const Color(0xFFEF4444)
                            : _isProcessing
                                ? AppColors.warning
                                : AppColors.textSecondary,
                        fontWeight:
                            _isListening || _isProcessing ? FontWeight.w500 : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: AppSizes.paddingLarge * 1.5),

                // Hey Neurix Wake Word Toggle
                _buildWakeWordCard(),
                const SizedBox(height: AppSizes.paddingMedium),

                // Subscription Status Card
                _buildSubscriptionCard(),
                const SizedBox(height: AppSizes.paddingMedium),

                // How Neurix Works Card
                _buildHowItWorksCard(),
                const SizedBox(height: AppSizes.paddingMedium),

                // All Memories Card
                FutureBuilder<List<Memory>>(
                  future: LocalDbService().getMemoriesByUserId(userId),
                  builder: (context, snapshot) {
                    final memories = snapshot.data ?? [];
                    final count = memories.length;

                    return _buildNavigationCardWithLimit(
                      title: 'All Memories',
                      count: count,
                      limit: _subscriptionService.memoryLimit,
                      icon: Icons.lightbulb_outline,
                      iconColor: AppColors.warning,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AllMemoriesScreen(),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: AppSizes.paddingMedium),

                // All Reminders Card
                FutureBuilder<List<Reminder>>(
                  future: LocalDbService().getActiveRemindersByUserId(userId),
                  builder: (context, snapshot) {
                    final reminders = snapshot.data ?? [];
                    final count = reminders.length;

                    return _buildNavigationCardWithLimit(
                      title: 'All Reminders',
                      count: count,
                      limit: _subscriptionService.reminderLimit,
                      icon: Icons.notifications_outlined,
                      iconColor: AppColors.primaryLight,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RemindersScreen(),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: AppSizes.paddingMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showProfileSheet(UserModel? user) {
    final authService = Provider.of<AuthService>(context, listen: false);
    // Get Google profile photo directly from Firebase Auth
    final googlePhotoUrl = FirebaseAuth.instance.currentUser?.photoURL;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ProfileSheet(
        user: user,
        authService: authService,
        googlePhotoUrl: googlePhotoUrl,
      ),
    );
  }

  Widget _buildWakeWordCard() {
    final isActive = _wakeWordService.isEnabled;
    final isListening = _wakeWordService.isListening;
    final hasError = _wakeWordService.errorMessage != null;

    return GlassCard(
      backgroundColor: isActive && isListening ? AppColors.success.withOpacity(0.06) : null,
      borderColor: isActive && isListening ? AppColors.success.withOpacity(0.15) : null,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (isActive && isListening ? AppColors.success : AppColors.primary).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.record_voice_over_rounded,
              color: isActive && isListening ? AppColors.success : AppColors.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSizes.paddingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"Hey Neurix"',
                  style: AppTextStyles.subheading,
                ),
                Text(
                  isActive && isListening
                      ? _wakeWordService.isEnrolled
                          ? 'Listening (voice enrolled)'
                          : 'Listening for wake word...'
                      : isActive && hasError
                          ? _wakeWordService.errorMessage!
                          : 'Voice activation disabled',
                  style: AppTextStyles.caption.copyWith(
                    color: isActive && isListening
                        ? AppColors.success
                        : isActive && hasError
                            ? AppColors.warning
                            : null,
                  ),
                ),
              ],
            ),
          ),
          if (_wakeWordService.isEnrolled)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: AppColors.textSecondary,
              tooltip: 'Re-enroll voice',
              onPressed: () async {
                await _wakeWordService.clearEnrollment();
                _showEnrollmentScreen();
              },
            ),
          Switch(
            value: isActive,
            onChanged: (value) async {
              await _wakeWordService.setEnabled(value);
              setState(() {});
              _notificationService.showVoiceNotification(
                title: 'Neurix',
                body: value && _wakeWordService.isListening
                    ? '"Hey Neurix" is active'
                    : 'Tap to speak',
              );
            },
            activeColor: AppColors.success,
            activeTrackColor: AppColors.success.withOpacity(0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    final isPro = _subscriptionService.isPro;

    return GlassCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const UpgradeScreen(),
          ),
        );
      },
      backgroundColor: isPro ? AppColors.success.withOpacity(0.08) : null,
      borderColor: isPro ? AppColors.success.withOpacity(0.2) : null,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPro
                  ? AppColors.success.withOpacity(0.15)
                  : AppColors.warning.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPro ? Icons.workspace_premium : Icons.star_outline_rounded,
              color: isPro ? AppColors.success : AppColors.warning,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSizes.paddingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPro ? 'Neurix Pro' : 'Free Plan',
                  style: AppTextStyles.subheading.copyWith(
                    color: isPro ? AppColors.success : null,
                  ),
                ),
                Text(
                  isPro
                      ? 'Unlimited memories & reminders'
                      : 'Tap to upgrade for unlimited',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          if (!isPro)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'UPGRADE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            )
          else
            const Icon(
              Icons.check_circle,
              color: AppColors.success,
            ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksCard() {
    return GlassCard(
      onTap: _showHowItWorksSheet,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSizes.paddingMedium),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How Neurix Works', style: AppTextStyles.subheading),
                Text(
                  'See what you can do with Neurix',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textHint),
        ],
      ),
    );
  }

  void _showHowItWorksSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.97),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    children: [
                      // Handle bar
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Title
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLarge),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Text('How Neurix Works', style: AppTextStyles.subheading),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingLarge),
                        child: Text(
                          'Speak naturally or tap the mic. Here\'s everything Neurix can do for you.',
                          style: AppTextStyles.caption,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Divider(color: Colors.white.withOpacity(0.08), height: 1),
                      // Scrollable content
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(AppSizes.paddingLarge),
                          children: [
                            _buildFeatureSection(
                              icon: Icons.record_voice_over_rounded,
                              iconColor: AppColors.primary,
                              title: 'Hey Neurix — Hands-free',
                              description: 'Say "Hey Neurix" from anywhere to activate Neurix without touching your phone. You must enroll your voice first — tap the "Hey Neurix" card on the home screen and follow the steps.',
                              examples: [
                                'Hey Neurix → I parked on level 3',
                                'Hey Neurix → Where did I park?',
                                'Hey Neurix → Remind me to call mom in 5 minutes',
                                'Hey Neurix → Cancel all reminders',
                              ],
                            ),
                            _buildFeatureSection(
                              icon: Icons.lightbulb_outline_rounded,
                              iconColor: AppColors.warning,
                              title: 'Save a Memory',
                              description: 'Tell Neurix anything you want to remember — items, locations, notes, passwords, anything.',
                              examples: [
                                'Hey Neurix → I parked my car on level 3, slot B12',
                                'Hey Neurix → My passport is in the top drawer',
                                'Hey Neurix → The wifi password is sunshine2024',
                                'Hey Neurix → Meeting with client is on Friday at 3pm',
                              ],
                            ),
                            _buildFeatureSection(
                              icon: Icons.search_rounded,
                              iconColor: AppColors.info,
                              title: 'Search your Memories',
                              description: 'Ask Neurix anything and it will find and read back the most relevant thing you\'ve saved.',
                              examples: [
                                'Hey Neurix → Where did I park?',
                                'Hey Neurix → Where is my passport?',
                                'Hey Neurix → What\'s the wifi password?',
                                'Hey Neurix → When is my meeting?',
                              ],
                            ),
                            _buildFeatureSection(
                              icon: Icons.alarm_rounded,
                              iconColor: AppColors.success,
                              title: 'Set a One-time Reminder',
                              description: 'Ask Neurix to remind you about something at a specific time or after a delay.',
                              examples: [
                                'Hey Neurix → Remind me to call mom in 5 minutes',
                                'Hey Neurix → Remind me to take medicine at 4pm',
                                'Hey Neurix → Remind me to check the oven after 30 minutes',
                              ],
                            ),
                            _buildFeatureSection(
                              icon: Icons.repeat_rounded,
                              iconColor: AppColors.primaryLight,
                              title: 'Set a Recurring Reminder',
                              description: 'Neurix can remind you repeatedly at a fixed interval — great for habits and routines.',
                              examples: [
                                'Hey Neurix → Remind me to drink water every 30 minutes',
                                'Hey Neurix → Remind me to stretch every 1 hour',
                                'Hey Neurix → Remind me to check my posture every 20 minutes',
                              ],
                            ),
                            _buildFeatureSection(
                              icon: Icons.cancel_outlined,
                              iconColor: AppColors.error,
                              title: 'Cancel a Specific Reminder',
                              description: 'Tell Neurix which reminder to stop and it will cancel just that one.',
                              examples: [
                                'Hey Neurix → Cancel the water reminder',
                                'Hey Neurix → Stop reminding me about medicine',
                                'Hey Neurix → Delete the posture reminder',
                              ],
                            ),
                            _buildFeatureSection(
                              icon: Icons.delete_sweep_rounded,
                              iconColor: AppColors.error,
                              title: 'Cancel All Reminders',
                              description: 'Clear all your active reminders at once with a single command.',
                              examples: [
                                'Hey Neurix → Cancel all reminders',
                                'Hey Neurix → Delete all my reminders',
                                'Hey Neurix → Stop all reminders',
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            );
          },
        );
      },
    );
  }

  Widget _buildFeatureSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required List<String> examples,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(title, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(description, style: AppTextStyles.caption),
          const SizedBox(height: 10),
          ...examples.map((example) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('  •  ', style: AppTextStyles.caption.copyWith(color: iconColor)),
                Expanded(
                  child: Text(
                    '"$example"',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white.withOpacity(0.55),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          )),
          Divider(color: Colors.white.withOpacity(0.06), height: 1),
        ],
      ),
    );
  }

  Widget _buildNavigationCardWithLimit({
    required String title,
    required int count,
    required int limit,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    final isUnlimited = limit == -1;
    final isAtLimit = !isUnlimited && count >= limit;

    return GlassCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 26,
            ),
          ),
          const SizedBox(width: AppSizes.paddingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.subheading,
                ),
                Text(
                  isUnlimited
                      ? '$count items'
                      : '$count / $limit',
                  style: AppTextStyles.caption.copyWith(
                    color: isAtLimit ? AppColors.warning : null,
                  ),
                ),
              ],
            ),
          ),
          if (isAtLimit)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: const Text(
                'FULL',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else
            Icon(
              Icons.chevron_right,
              color: AppColors.textHint,
            ),
        ],
      ),
    );
  }

}

class _ProfileSheet extends StatefulWidget {
  final UserModel? user;
  final AuthService authService;
  final String? googlePhotoUrl;

  const _ProfileSheet({required this.user, required this.authService, this.googlePhotoUrl});

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late TextEditingController _nameController;
  Map<Permission, PermissionStatus> _statuses = {};
  bool _loadingPermissions = true;
  bool _savingProfile = false;
  String? _selectedAvatar;

  static const List<String> _avatars = [
    'https://api.dicebear.com/9.x/notionists/png?seed=Felix&backgroundColor=b6e3f4',
    'https://api.dicebear.com/9.x/notionists/png?seed=James&backgroundColor=c0aede',
    'https://api.dicebear.com/9.x/notionists/png?seed=Oliver&backgroundColor=d1f4d9',
    'https://api.dicebear.com/9.x/notionists/png?seed=Ethan&backgroundColor=ffeaa7',
    'https://api.dicebear.com/9.x/notionists/png?seed=Daniel&backgroundColor=dfe6e9',
    'https://api.dicebear.com/9.x/notionists/png?seed=Sophia&backgroundColor=ffdfbf',
    'https://api.dicebear.com/9.x/notionists/png?seed=Emma&backgroundColor=ffd5dc',
    'https://api.dicebear.com/9.x/notionists/png?seed=Aria&backgroundColor=e8daef',
    'https://api.dicebear.com/9.x/notionists/png?seed=Grace&backgroundColor=fadbd8',
    'https://api.dicebear.com/9.x/notionists/png?seed=Chloe&backgroundColor=abebc6',
    'https://api.dicebear.com/9.x/notionists/png?seed=Isabella&backgroundColor=d5f5e3',
    'https://api.dicebear.com/9.x/notionists/png?seed=Violet&backgroundColor=d2b4de',
    'https://api.dicebear.com/9.x/notionists/png?seed=Nora&backgroundColor=f9e79f',
    'https://api.dicebear.com/9.x/notionists/png?seed=Elena&backgroundColor=aed6f1',
    'https://api.dicebear.com/9.x/notionists/png?seed=Ruby&backgroundColor=f5b7b1',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user?.displayName ?? '');
    _selectedAvatar = widget.user?.photoUrl;
    _checkPermissions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    final checked = {
      Permission.notification: await Permission.notification.status,
      Permission.microphone: await Permission.microphone.status,
      Permission.scheduleExactAlarm: await Permission.scheduleExactAlarm.status,
      Permission.systemAlertWindow: await Permission.systemAlertWindow.status,
    };
    if (mounted) {
      setState(() {
        _statuses = checked;
        _loadingPermissions = false;
      });
    }
  }

  Future<void> _requestPermission(Permission permission) async {
    final status = await permission.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    } else {
      await permission.request();
    }
    await _checkPermissions();
  }

  Widget _buildAvatarOption(String avatarUrl, {String? label}) {
    final isSelected = _selectedAvatar == avatarUrl;
    return GestureDetector(
      onTap: () => setState(() => _selectedAvatar = avatarUrl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8)]
                  : [],
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.glass,
              backgroundImage: NetworkImage(avatarUrl),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    setState(() => _savingProfile = true);

    final success = await widget.authService.updateUserProfile(
      displayName: newName,
      photoUrl: _selectedAvatar,
    );

    setState(() => _savingProfile = false);

    if (success && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.glassBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // --- Profile Section ---
              const Text(
                'Profile',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text),
              ),
              const SizedBox(height: 16),

              // Avatar Selection
              const Text('Choose Avatar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  // Google profile photo as first option
                  if (widget.googlePhotoUrl != null)
                    _buildAvatarOption(widget.googlePhotoUrl!, label: 'Google'),
                  // DiceBear avatars
                  ..._avatars.map((avatarUrl) => _buildAvatarOption(avatarUrl)),
                ],
              ),
              const SizedBox(height: 20),

              // Name Field
              TextField(
                controller: _nameController,
                style: const TextStyle(color: AppColors.text),
                decoration: AppInputDecorations.textField(
                  label: 'Display Name',
                  icon: Icons.person_outline,
                ),
              ),
              const SizedBox(height: 16),

              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _savingProfile ? null : _saveProfile,
                  child: _savingProfile
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 28),

              // --- Permissions Section ---
              const Text(
                'Permissions',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.text),
              ),
              const SizedBox(height: 8),
              const Text(
                'Grant permissions for the best experience',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              if (_loadingPermissions)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: AppColors.primary)))
              else ...[
                _buildPermissionTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Reminders, alarms & voice control',
                  permission: Permission.notification,
                ),
                _buildPermissionTile(
                  icon: Icons.mic_outlined,
                  title: 'Microphone',
                  subtitle: 'Voice commands & speech recognition',
                  permission: Permission.microphone,
                ),
                _buildPermissionTile(
                  icon: Icons.alarm_outlined,
                  title: 'Exact Alarms',
                  subtitle: 'Precise reminder scheduling',
                  permission: Permission.scheduleExactAlarm,
                ),
                _buildPermissionTile(
                  icon: Icons.picture_in_picture_outlined,
                  title: 'Overlay',
                  subtitle: 'Floating voice assistant bubble',
                  permission: Permission.systemAlertWindow,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Permission permission,
  }) {
    final status = _statuses[permission];
    final isGranted = status?.isGranted ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        tileColor: AppColors.glass,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isGranted ? AppColors.success : AppColors.primary).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: isGranted ? AppColors.success : AppColors.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        trailing: isGranted
            ? const Icon(Icons.check_circle, color: AppColors.success)
            : TextButton(
                onPressed: () => _requestPermission(permission),
                child: const Text('Grant'),
              ),
      ),
    );
  }
}