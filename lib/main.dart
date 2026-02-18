import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/alarm_screen.dart';
import 'services/auth_service.dart';
import 'services/sync_service.dart';
import 'services/voice_service.dart';
import 'services/llm_service.dart';
import 'services/alarm_helper_service.dart';
import 'utils/constants.dart';
import 'models/user_model.dart';
import 'widgets/floating_bubble.dart';

/// Global navigator key for navigating from notification callbacks
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Pending alarm data - used when app launches from notification
int? _pendingAlarmId;
String? _pendingAlarmMessage;

/// Overlay entry point - runs in separate isolate
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: FloatingBubble(),
  ));
}

/// Handle notification tap callback
void _onNotificationTap(NotificationResponse response) async {
  print('[Main] Notification tapped: ${response.payload}');
  if (response.payload != null && response.payload!.contains('|')) {
    final parts = response.payload!.split('|');
    if (parts.length >= 2) {
      final alarmId = int.tryParse(parts[0]);
      final message = parts[1];
      if (alarmId != null) {
        // Get reminder ID from SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final reminderId = prefs.getString('active_alarm_reminder_id');
        _navigateToAlarmScreen(alarmId, message, reminderId);
      }
    }
  }
}

/// Navigate to alarm screen
void _navigateToAlarmScreen(int alarmId, String message, String? reminderId) {
  print('[Main] Navigating to alarm screen: $alarmId, $message, reminderId: $reminderId');
  final navigator = navigatorKey.currentState;
  if (navigator != null) {
    navigator.push(
      MaterialPageRoute(
        builder: (context) => AlarmScreen(
          message: message,
          alarmId: alarmId,
          reminderId: reminderId,
        ),
      ),
    );
  } else {
    // Navigator not ready yet - store for later
    _pendingAlarmId = alarmId;
    _pendingAlarmMessage = message;
    print('[Main] Navigator not ready, storing pending alarm');
  }
}

/// Check for active alarm on startup
/// Only show alarm screen if the alarm was triggered recently (within last 5 minutes)
Future<void> _checkForActiveAlarm() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final activeAlarmId = prefs.getInt('active_alarm_id');
    final activeAlarmMessage = prefs.getString('active_alarm_message');
    final activeAlarmTimestamp = prefs.getInt('active_alarm_timestamp');

    if (activeAlarmId != null && activeAlarmMessage != null && activeAlarmTimestamp != null) {
      // Check if the alarm was triggered recently (within last 5 minutes)
      final alarmTime = DateTime.fromMillisecondsSinceEpoch(activeAlarmTimestamp);
      final now = DateTime.now();
      final difference = now.difference(alarmTime);

      if (difference.inMinutes < 5) {
        print('[Main] Found recent active alarm: $activeAlarmId, $activeAlarmMessage (${difference.inSeconds}s ago)');
        _pendingAlarmId = activeAlarmId;
        _pendingAlarmMessage = activeAlarmMessage;
      } else {
        // Alarm is too old (more than 5 minutes) - clean it up
        print('[Main] Found old active alarm (${difference.inMinutes}min ago), cleaning up: $activeAlarmId');
        await prefs.remove('active_alarm_id');
        await prefs.remove('active_alarm_message');
        await prefs.remove('active_alarm_timestamp');
        await prefs.remove('active_alarm_reminder_id');
      }
    } else if (activeAlarmId != null || activeAlarmMessage != null) {
      // Incomplete data - clean it up
      print('[Main] Found incomplete active alarm data, cleaning up');
      await prefs.remove('active_alarm_id');
      await prefs.remove('active_alarm_message');
      await prefs.remove('active_alarm_timestamp');
      await prefs.remove('active_alarm_reminder_id');
    }
  } catch (e) {
    print('[Main] Error checking for active alarm: $e');
  }
}

/// Initialize notification channels early - required for foreground services
Future<void> _initializeNotificationChannels() async {
  final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  // Initialize the plugin with tap callback
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await notifications.initialize(
    initSettings,
    onDidReceiveNotificationResponse: _onNotificationTap,
  );

  final androidPlugin = notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();

  if (androidPlugin != null) {
    // Voice control notification channel
    const voiceChannel = AndroidNotificationChannel(
      'neurix_voice',
      'Neurix Voice',
      description: 'Voice interaction controls',
      importance: Importance.low,
    );
    await androidPlugin.createNotificationChannel(voiceChannel);

    // Background voice service channel (for foreground service)
    const bgVoiceChannel = AndroidNotificationChannel(
      'neurix_voice_bg',
      'Neurix Voice Background',
      description: 'Voice recording in background',
      importance: Importance.low,
    );
    await androidPlugin.createNotificationChannel(bgVoiceChannel);

    // Reminders notification channel
    const remindersChannel = AndroidNotificationChannel(
      'neurix_reminders',
      'Neurix Reminders',
      description: 'Reminder notifications',
      importance: Importance.high,
    );
    await androidPlugin.createNotificationChannel(remindersChannel);

    // Alarms notification channel (high priority for full screen intent)
    const alarmsChannel = AndroidNotificationChannel(
      'neurix_alarms',
      'Neurix Alarms',
      description: 'Alarm notifications with full screen',
      importance: Importance.max,
    );
    await androidPlugin.createNotificationChannel(alarmsChannel);

    print('Notification channels created');
  }
}

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Load environment variables
    try {
      await dotenv.load(fileName: '.env');
      print('Environment variables loaded successfully');
      print('GROQ_API_KEY present: ${dotenv.env['GROQ_API_KEY']?.isNotEmpty ?? false}');
      print('NOMIC_API_KEY present: ${dotenv.env['NOMIC_API_KEY']?.isNotEmpty ?? false}');
    } catch (e) {
      print('Warning: Could not load .env file: $e');
    }

    // Check for active alarm before anything else
    await _checkForActiveAlarm();

    // Initialize notification channels early (required for foreground services)
    await _initializeNotificationChannels();

    // Initialize Firebase
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyD6ObWDugkvvE7aGP5cSh-015gvm22_V1M',
        appId: '1:1026337369775:android:87d7f482ccdd9ff38a2e5a',
        messagingSenderId: '1026337369775',
        projectId: 'neuro-app-93c3d',
        storageBucket: 'neuro-app-93c3d.firebasestorage.app',
      ),
    );
    
    // Initialize Firestore
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      print('Firestore initialized successfully');
    } catch (e) {
      print('Error initializing Firestore: $e');
    }
    
    runApp(const MyApp());
  } catch (e) {
    print('Error initializing app: $e');
    // Show error screen
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Error initializing app. Please check your internet connection and try again.',
            style: TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializeServices(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSizes.paddingLarge),
                  child: Text(
                    'Error initializing services. Please restart the app.',
                    style: AppTextStyles.body.copyWith(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: AppColors.background,
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/icon/neurixLogo_white.png',
                      width: 80,
                      height: 80,
                    ),
                    const SizedBox(height: AppSizes.paddingLarge),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final AuthService authService = snapshot.data as AuthService;

        return MultiProvider(
          providers: [
            Provider<AuthService>.value(value: authService),
            StreamProvider<AuthStatus>(
              create: (_) => authService.authStatusStream,
              initialData: authService.currentAuthStatus,
            ),
            StreamProvider<UserModel?>(
              create: (_) => authService.user,
              initialData: authService.currentUser,
            ),
            ChangeNotifierProvider<VoiceService>(
              create: (_) => VoiceService(),
            ),
            Provider<SyncService>(
              create: (_) => authService.syncService,
            ),
            Provider<LLMService>(
              create: (_) => LLMService(), // Will be initialized in _initializeServices
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            title: 'Neurix',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: AppColors.background,
              primaryColor: AppColors.primary,
              colorScheme: const ColorScheme.dark(
                primary: AppColors.primary,
                secondary: AppColors.primaryLight,
                surface: AppColors.surface,
                error: AppColors.error,
              ),
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
                titleTextStyle: TextStyle(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                iconTheme: IconThemeData(color: AppColors.text),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.text,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSizes.paddingMedium,
                    horizontal: AppSizes.paddingLarge,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.text,
                  side: BorderSide(color: AppColors.glassBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                  ),
                ),
              ),
              cardTheme: CardTheme(
                color: AppColors.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                ),
              ),
              dividerColor: AppColors.glassBorder,
              bottomSheetTheme: const BottomSheetThemeData(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
              ),
              dialogTheme: DialogTheme(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.borderRadius),
                ),
              ),
              floatingActionButtonTheme: const FloatingActionButtonThemeData(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.text,
              ),
              snackBarTheme: SnackBarThemeData(
                backgroundColor: AppColors.surface,
                contentTextStyle: const TextStyle(color: AppColors.text),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                behavior: SnackBarBehavior.floating,
              ),
              visualDensity: VisualDensity.adaptivePlatformDensity,
            ),
            home: const AuthWrapper(),
          ),
        );
      },
    );
  }

  Future<AuthService> _initializeServices() async {
    try {
      // Initialize Auth Service
      final authService = AuthService();
      await authService.initialize();

      // Initialize LLM Service (singleton) - don't block on failure
      print('Initializing LLM Service...');
      final llmService = LLMService();
      try {
        await llmService.initialize();
        print('LLM Service ready');
      } catch (e) {
        print('LLM Service initialization failed (will use fallback): $e');
        // Continue without LLM - fallback will be used
      }

      return authService;
    } catch (e) {
      print('Error initializing services: $e');
      rethrow;
    }
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _checkedPendingAlarm = false;
  bool _isShowingAlarm = false;
  int? _lastShownAlarmTimestamp;

  @override
  void initState() {
    super.initState();
    // Register lifecycle observer to detect when app comes to foreground
    WidgetsBinding.instance.addObserver(this);

    // Initialize the alarm helper service to receive events from native side
    AlarmHelperService.initialize(onCheckAlarm: () {
      print('[AuthWrapper] Native check_alarm event received');
      // Add a small delay to allow the alarm callback to store data first
      // The alarm callback runs in a background isolate and may take a moment
      _checkForActiveAlarmWithRetry();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AlarmHelperService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('[AuthWrapper] App lifecycle changed: $state');

    // When app comes to foreground (resumed), check for active alarms
    if (state == AppLifecycleState.resumed) {
      _checkForActiveAlarmOnResume();
    }
  }

  /// Check for active alarm with retry logic
  /// This is needed because the alarm callback runs in a background isolate
  /// and may not have stored the data yet when the native event fires
  Future<void> _checkForActiveAlarmWithRetry() async {
    // Try immediately first
    final found = await _checkForActiveAlarmOnResume();
    if (found) return;

    // If not found, retry a few times with delays
    // This handles the race condition where the native event fires before the alarm callback stores data
    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      print('[AuthWrapper] Retry ${i + 1}/5 checking for active alarm...');
      final foundOnRetry = await _checkForActiveAlarmOnResume();
      if (foundOnRetry) return;
    }
    print('[AuthWrapper] No active alarm found after retries');
  }

  /// Check for active alarm when app resumes from background
  /// This handles the case where an alarm fires while app is in background
  /// Returns true if an alarm was found and shown
  Future<bool> _checkForActiveAlarmOnResume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Reload to get fresh data (important after background isolate writes)
      await prefs.reload();

      final activeAlarmId = prefs.getInt('active_alarm_id');
      final activeAlarmMessage = prefs.getString('active_alarm_message');
      final activeAlarmTimestamp = prefs.getInt('active_alarm_timestamp');
      final activeAlarmReminderId = prefs.getString('active_alarm_reminder_id');

      print('[AuthWrapper] Checking for active alarm on resume: id=$activeAlarmId, msg=$activeAlarmMessage, ts=$activeAlarmTimestamp, reminderId=$activeAlarmReminderId');
      print('[AuthWrapper] _isShowingAlarm=$_isShowingAlarm, _lastShownAlarmTimestamp=$_lastShownAlarmTimestamp');

      if (activeAlarmId != null && activeAlarmMessage != null && activeAlarmTimestamp != null) {
        // Check if the alarm was triggered recently (within last 5 minutes)
        final alarmTime = DateTime.fromMillisecondsSinceEpoch(activeAlarmTimestamp);
        final now = DateTime.now();
        final difference = now.difference(alarmTime);

        if (difference.inMinutes < 5) {
          // Check if this is a NEW alarm (different timestamp from last shown)
          if (_lastShownAlarmTimestamp == activeAlarmTimestamp) {
            print('[AuthWrapper] Same alarm timestamp, skipping (already shown)');
            return true; // Return true since we found it, just already shown
          }

          print('[AuthWrapper] Found recent active alarm on resume: $activeAlarmId (${difference.inSeconds}s ago)');

          // If already showing an alarm, the old screen should have been dismissed
          // Reset the flag to allow showing the new alarm
          if (_isShowingAlarm) {
            print('[AuthWrapper] Was showing alarm, resetting flag for new alarm');
            _isShowingAlarm = false;
          }

          // Record this alarm timestamp to avoid showing it again
          _lastShownAlarmTimestamp = activeAlarmTimestamp;

          _showAlarmScreen(activeAlarmId, activeAlarmMessage, activeAlarmReminderId);
          return true;
        } else {
          // Alarm is too old - clean it up
          print('[AuthWrapper] Active alarm too old (${difference.inMinutes}min), cleaning up');
          await prefs.remove('active_alarm_id');
          await prefs.remove('active_alarm_message');
          await prefs.remove('active_alarm_timestamp');
          await prefs.remove('active_alarm_reminder_id');
          return false;
        }
      }
      return false;
    } catch (e) {
      print('[AuthWrapper] Error checking for active alarm on resume: $e');
      return false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check for pending alarm after authentication is complete
    final authStatus = context.read<AuthStatus>();
    if (!_checkedPendingAlarm && authStatus == AuthStatus.authenticated) {
      _checkedPendingAlarm = true;
      // Use a slight delay to ensure the home screen is fully mounted
      Future.delayed(const Duration(milliseconds: 500), () {
        _checkAndShowPendingAlarm();
      });
    }
  }

  void _checkAndShowPendingAlarm() async {
    if (_pendingAlarmId != null && _pendingAlarmMessage != null) {
      final alarmId = _pendingAlarmId!;
      final message = _pendingAlarmMessage!;

      // Clear the pending alarm
      _pendingAlarmId = null;
      _pendingAlarmMessage = null;

      // Get the reminder ID if available
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final reminderId = prefs.getString('active_alarm_reminder_id');

      print('[AuthWrapper] Showing pending alarm: $alarmId, $message, reminderId: $reminderId');
      _showAlarmScreen(alarmId, message, reminderId);
    }
  }

  void _showAlarmScreen(int alarmId, String message, String? reminderId) {
    if (_isShowingAlarm) {
      print('[AuthWrapper] Already showing alarm screen, skipping');
      return;
    }

    _isShowingAlarm = true;

    // Use the global navigator key to ensure we push on the root navigator
    final navigator = navigatorKey.currentState;
    if (navigator != null && mounted) {
      navigator.push(
        MaterialPageRoute(
          builder: (context) => AlarmScreen(
            message: message,
            alarmId: alarmId,
            reminderId: reminderId,
          ),
        ),
      ).then((_) {
        // Reset flag when alarm screen is dismissed
        _isShowingAlarm = false;
        print('[AuthWrapper] Alarm screen dismissed');
      });
    } else {
      print('[AuthWrapper] Navigator not available, trying local context');
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AlarmScreen(
              message: message,
              alarmId: alarmId,
              reminderId: reminderId,
            ),
          ),
        ).then((_) {
          _isShowingAlarm = false;
          print('[AuthWrapper] Alarm screen dismissed');
        });
      } else {
        _isShowingAlarm = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authStatus = context.watch<AuthStatus>();

    switch (authStatus) {
      case AuthStatus.authenticated:
        return const HomeScreen();
      case AuthStatus.loading:
        return const LoadingScreen();
      case AuthStatus.error:
        return const ErrorScreen();
      case AuthStatus.unauthenticated:
      default:
        return const LoginScreen();
    }
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icon/neurixLogo_white.png',
              width: 80,
              height: 80,
            ),
            const SizedBox(height: AppSizes.paddingLarge),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingLarge),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: AppSizes.paddingLarge),
              Text(
                'Something went wrong',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppSizes.paddingSmall),
              Text(
                'Please try again later',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSizes.paddingLarge * 1.5),
              ElevatedButton(
                onPressed: () {
                  context.read<AuthService>().signOut();
                },
                child: const Text('Return to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
