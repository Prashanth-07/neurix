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
import '../models/user_model.dart';
import '../models/memory_model.dart';
import '../models/reminder_model.dart';
import '../utils/constants.dart';
import '../widgets/confirmation_dialog.dart';
import 'all_memories_screen.dart';
import 'reminders_screen.dart';
import 'upgrade_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final NotificationService _notificationService = NotificationService();
  final ReminderService _reminderService = ReminderService();
  final SubscriptionService _subscriptionService = SubscriptionService();

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
          _listeningFromNotification = false;
        });
        // Only speak error if not triggered from notification (to avoid TTS being captured)
        if (!wasFromNotification) {
          _speak('Sorry, I couldn\'t hear you. Please try again.');
        }
      },
    );
    print('[HomeScreen] Speech initialized: $_speechInitialized');
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  Future<void> _startListening() async {
    print('[HomeScreen] ========================================');
    print('[HomeScreen] === STARTING LISTENING ===');
    print('[HomeScreen] ========================================');

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
  }

  /// ===========================================
  /// MAIN VOICE INPUT PROCESSING FLOW
  /// ===========================================
  /// 1. LLM Call 1: Detect intent (save/search/reminder/cancel_reminder/unclear)
  /// 2. Route to appropriate handler based on intent
  /// 3. Speak response and reset UI
  Future<void> _processVoiceInput() async {
    if (_transcribedText.isEmpty) return;

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
          return;
        }
      } else if (intent == 'cancel_reminder') {
        // Delete Reminder: No confirmation needed - execute immediately
        print('[FLOW] -> DELETE REMINDER');
        response = await _handleCancelReminder(_transcribedText);
      } else {
        // Unclear: Ask for clarification and keep listening
        print('[FLOW] -> UNCLEAR, restarting listening');
        response = "I didn't understand. Can you please be more clear?";
        setState(() { _statusText = response; _isProcessing = false; });
        await _speak(response);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) _startListening();
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
    } catch (e) {
      print('[FLOW] ERROR: $e');
      setState(() { _statusText = 'Something went wrong'; _isProcessing = false; });
      await _speak('Sorry, something went wrong.');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) setState(() { _statusText = 'Tap to speak'; });
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
        _notificationService.showVoiceNotification();

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
        // App went to background - notification should persist (ongoing: true)
        // Re-show to ensure it's still there
        _notificationService.showVoiceNotification();
        break;
      case AppLifecycleState.detached:
        // App is being terminated - cancel all notifications
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
    await _notificationService.showVoiceNotification();
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
    final authService = Provider.of<AuthService>(context);
    final UserModel? user = authService.currentUser;
    final userId = user?.uid ?? 'anonymous';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Neurix'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSizes.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Profile Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSizes.paddingMedium),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: AppColors.primary.withOpacity(0.1),
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
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.person_outline,
                                size: 25,
                                color: AppColors.primary,
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
                            Text(
                              user?.email ?? '',
                              style: AppTextStyles.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.paddingLarge),

              // Big Mic Button
              Center(
                child: GestureDetector(
                  onTap: _isProcessing
                      ? null
                      : (_isListening ? _stopListening : _startListening),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isListening ? 140 : 120,
                    height: _isListening ? 140 : 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isListening
                            ? [Colors.red, Colors.redAccent]
                            : _isProcessing
                                ? [Colors.orange, Colors.orangeAccent]
                                : [Colors.deepPurple, Colors.purpleAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening
                                  ? Colors.red
                                  : _isProcessing
                                      ? Colors.orange
                                      : Colors.deepPurple)
                              .withOpacity(0.4),
                          blurRadius: _isListening ? 30 : 20,
                          spreadRadius: _isListening ? 4 : 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isListening
                          ? Icons.stop
                          : _isProcessing
                              ? Icons.hourglass_top
                              : Icons.mic,
                      size: 60,
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
                        ? Colors.red.withOpacity(0.1)
                        : _isProcessing
                            ? Colors.orange.withOpacity(0.1)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusText,
                    style: AppTextStyles.body.copyWith(
                      color: _isListening
                          ? Colors.red
                          : _isProcessing
                              ? Colors.orange
                              : Colors.grey[600],
                      fontWeight:
                          _isListening || _isProcessing ? FontWeight.w500 : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.paddingLarge),

              // Subscription Status Card
              _buildSubscriptionCard(),
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
                    iconColor: Colors.amber,
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
                    iconColor: Colors.deepPurple,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    final isPro = _subscriptionService.isPro;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
      ),
      color: isPro ? Colors.green.withOpacity(0.1) : null,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const UpgradeScreen(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingMedium),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isPro
                      ? Colors.green.withOpacity(0.2)
                      : Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPro ? Icons.workspace_premium : Icons.star_outline,
                  color: isPro ? Colors.green : Colors.amber,
                  size: 28,
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
                        color: isPro ? Colors.green : null,
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
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'UPGRADE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                ),
            ],
          ),
        ),
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

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingMedium),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 28,
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
                        color: isAtLimit ? Colors.orange : null,
                      ),
                    ),
                  ],
                ),
              ),
              if (isAtLimit)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'FULL',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationCard({
    required String title,
    required int count,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.borderRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingMedium),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppSizes.paddingMedium),
              Expanded(
                child: Text(
                  '$title ($count)',
                  style: AppTextStyles.subheading,
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) {
          return 'Just now';
        }
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
} 