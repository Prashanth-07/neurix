import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/sync_service.dart';
import 'utils/constants.dart';
import 'models/user_model.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
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
            home: Scaffold(
              body: Center(
                child: Text(
                  'Error initializing services: ${snapshot.error}',
                  style: TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return MaterialApp(
            home: const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
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
              initialData: AuthStatus.unauthenticated,
            ),
            StreamProvider<UserModel?>(
              create: (_) => authService.user,
              initialData: null,
            ),
          ],
          child: MaterialApp(
            title: 'Neurix',
            theme: ThemeData(
              primarySwatch: Colors.deepPurple,
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
      final authService = AuthService();
      await authService.initialize();
      return authService;
    } catch (e) {
      print('Error initializing services: $e');
      throw e;
    }
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

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
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSizes.paddingMedium),
            Text(
              'Something went wrong',
              style: AppTextStyles.heading.copyWith(
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSizes.paddingSmall),
            Text(
              'Please try again later',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: AppSizes.paddingLarge),
            ElevatedButton(
              onPressed: () {
                context.read<AuthService>().signOut();
              },
              child: const Text('Return to Login'),
            ),
          ],
        ),
      ),
    );
  }
}
