import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import 'sync_service.dart';
import 'package:flutter/foundation.dart';

enum AuthStatus {
  unauthenticated,  // User is not signed in
  loading,          // Authentication in progress
  authenticated,    // User is signed in and data loaded
  error,           // Authentication error occurred
}

class AuthResult {
  final bool success;
  final UserModel? user;
  final String message;
  
  AuthResult({
    required this.success,
    this.user,
    required this.message,
  });
  
  @override
  String toString() {
    return 'AuthResult(success: $success, message: $message)';
  }
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  GoogleSignIn? _googleSignIn;

  // Initialize SyncService
  final SyncService _syncService = SyncService();
  
  // Stream controllers for user state and authentication status
  final StreamController<UserModel?> _userController = StreamController<UserModel?>.broadcast();
  final StreamController<AuthStatus> _authStatusController = StreamController<AuthStatus>.broadcast();
  
  // Current user and auth status
  UserModel? _currentUser;
  AuthStatus _currentAuthStatus = AuthStatus.unauthenticated;
  bool _isInitialized = false;
  StreamSubscription<User?>? _authStateSubscription;
  
  // Getters for streams
  Stream<UserModel?> get user => _userController.stream;
  Stream<AuthStatus> get authStatusStream => _authStatusController.stream;
  Stream<UserModel?> get userStream => _userController.stream; // For backward compatibility
  
  // Getters for current state
  UserModel? get currentUser => _currentUser;
  AuthStatus get currentAuthStatus => _currentAuthStatus;
  SyncService get syncService => _syncService;

  // Initialize the auth service
  Future<void> initialize() async {
    try {
      print('Initializing AuthService...');
      
      // Listen to auth state changes
      _auth.authStateChanges().listen((User? firebaseUser) async {
        try {
          print('Firebase auth state changed: ${firebaseUser?.email}');
          
          if (firebaseUser == null) {
            _currentUser = null;
            _userController.add(null);
          } else {
            // Convert Firebase User to UserModel
            final userModel = UserModel(
              uid: firebaseUser.uid,
              email: firebaseUser.email ?? '',
              displayName: firebaseUser.displayName,
              photoUrl: firebaseUser.photoURL,
              createdAt: DateTime.now(),
              lastLoginAt: DateTime.now(),
              isEmailVerified: firebaseUser.emailVerified,
            );

            _currentUser = userModel;
            _userController.add(userModel);

            // Update auth status to authenticated immediately
            _updateAuthStatus(AuthStatus.authenticated);

            await _handleUserLogin(firebaseUser.uid);
          }
        } catch (e) {
          // Suppress known Pigeon type cast errors from google_sign_in plugin
          if (!e.toString().contains('PigeonUserDetails')) {
            print('Error handling auth state change: $e');
            _userController.addError(e);
          }
          // Even if there's a Pigeon error, if we have a current user, mark as authenticated
          if (_currentUser != null) {
            _updateAuthStatus(AuthStatus.authenticated);
          }
        }
      }, onError: (error) {
        // Suppress known Pigeon type cast errors from google_sign_in plugin
        if (!error.toString().contains('PigeonUserDetails')) {
          print('Auth state change error: $error');
          _userController.addError(error);
        }
      });

      // Listen to sync status changes
      _syncService.syncStatusStream.listen((status) {
        print('Sync status changed: $status');
        // Update auth status based on sync status if needed
        _updateAuthStatus(_mapSyncToAuthStatus(status));
      });
      
      _isInitialized = true;
      print('AuthService initialized successfully');

      // Check if user is already logged in and emit the correct status
      if (_auth.currentUser != null) {
        print('User already logged in: ${_auth.currentUser!.email}');
        final firebaseUser = _auth.currentUser!;
        final userModel = UserModel(
          uid: firebaseUser.uid,
          email: firebaseUser.email ?? '',
          displayName: firebaseUser.displayName,
          photoUrl: firebaseUser.photoURL,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
          isEmailVerified: firebaseUser.emailVerified,
        );
        _currentUser = userModel;
        _userController.add(userModel);
        _updateAuthStatus(AuthStatus.authenticated);
      }
    } catch (e) {
      print('Error initializing AuthService: $e');
      _updateAuthStatus(AuthStatus.error);
      throw e;
    }
  }

  Future<void> _handleUserLogin(String uid) async {
    try {
      print('Starting user login for UID: $uid');
      await _syncService.sync();
    } catch (e) {
      print('Error during user login: $e');
      // Don't throw here to prevent auth state listener from breaking
    }
  }

  // Register with email & password
  Future<AuthResult> registerWithEmail(String email, String password) async {
    print('Starting email registration for: $email');
    _updateAuthStatus(AuthStatus.loading);
    
    try {
      // Step 1: Create Firebase Auth account
      UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      User? firebaseUser = credential.user;
      if (firebaseUser == null) {
        _updateAuthStatus(AuthStatus.error);
        return AuthResult(
          success: false,
          message: 'Failed to create Firebase account',
        );
      }
      
      print('Firebase account created successfully');
      
      // Step 2: Create UserModel with additional data
      UserModel newUser = UserModel(
        uid: firebaseUser.uid,
        email: firebaseUser.email!,
        displayName: firebaseUser.displayName,
        photoUrl: firebaseUser.photoURL,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
        isEmailVerified: firebaseUser.emailVerified,
        preferences: {
          'theme': 'light',
          'notifications': true,
          'language': 'en',
        },
      );
      
      // Step 3: Save user data using SyncService
      UserRegistrationResult registrationResult = await _syncService.registerUser(newUser);
      
      if (registrationResult.success) {
        _updateUser(newUser);
        _updateAuthStatus(AuthStatus.authenticated);
        
        print('User registration completed successfully');
        return AuthResult(
          success: true,
          user: newUser,
          message: registrationResult.message,
        );
      } else {
        // Registration failed - clean up Firebase account
        await firebaseUser.delete();
        _updateAuthStatus(AuthStatus.error);
        
        return AuthResult(
          success: false,
          message: 'Failed to save user data: ${registrationResult.message}',
        );
      }
      
    } on FirebaseAuthException catch (e) {
      _updateAuthStatus(AuthStatus.error);
      print('Firebase registration error: ${e.code} - ${e.message}');
      
      String message = _getFirebaseErrorMessage(e.code);
      return AuthResult(
        success: false,
        message: message,
      );
      
    } catch (e) {
      // Suppress known Pigeon type cast errors from google_sign_in plugin
      if (!e.toString().contains('PigeonUserDetails')) {
        _updateAuthStatus(AuthStatus.error);
        print('Registration error: $e');

        return AuthResult(
          success: false,
          message: 'Registration failed: $e',
        );
      }
      // If it's the known Pigeon error, just ignore it - auth already succeeded
      return AuthResult(success: true, message: 'Registration completed');
    }
  }

  // Sign in with email & password
  Future<AuthResult> signInWithEmail(String email, String password) async {
    print('Starting email sign-in for: $email');
    _updateAuthStatus(AuthStatus.loading);
    
    try {
      // Step 1: Authenticate with Firebase
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      User? firebaseUser = credential.user;
      if (firebaseUser == null) {
        _updateAuthStatus(AuthStatus.error);
        return AuthResult(
          success: false,
          message: 'Authentication failed',
        );
      }
      
      print('Firebase authentication successful');
      
      // Step 2: User data will be loaded automatically via _onAuthStateChanged
      // No need to manually call loginUser here
      
      return AuthResult(
        success: true,
        message: 'Sign-in successful',
      );
      
    } on FirebaseAuthException catch (e) {
      _updateAuthStatus(AuthStatus.error);
      print('Firebase sign-in error: ${e.code} - ${e.message}');
      
      String message = _getFirebaseErrorMessage(e.code);
      return AuthResult(
        success: false,
        message: message,
      );
      
    } catch (e) {
      // Suppress known Pigeon type cast errors from google_sign_in plugin
      if (!e.toString().contains('PigeonUserDetails')) {
        _updateAuthStatus(AuthStatus.error);
        print('Sign-in error: $e');

        return AuthResult(
          success: false,
          message: 'Sign-in failed: $e',
        );
      }
      // If it's the known Pigeon error, just ignore it - auth already succeeded
      return AuthResult(success: true, message: 'Sign-in completed');
    }
  }

  // Sign in with Google
  Future<AuthResult> signInWithGoogle() async {
    print('Starting Google sign-in');
    _updateAuthStatus(AuthStatus.loading);

    try {
      // Initialize GoogleSignIn if not already done
      _googleSignIn ??= GoogleSignIn(
        scopes: ['email'],
      );

      // Step 1: Google Sign-In flow
      GoogleSignInAccount? googleUser;

      if (kIsWeb) {
        print('Web platform detected - using web-specific sign in flow');
        // For web testing, try silent sign in first
        try {
          googleUser = await _googleSignIn!.signInSilently();
          print('Silent sign in ${googleUser != null ? 'successful' : 'failed'}');
        } catch (e) {
          print('Silent sign-in failed: $e');
        }

        // If silent sign in fails, use normal sign in with additional error handling
        if (googleUser == null) {
          try {
            googleUser = await _googleSignIn!.signIn();
          } catch (e) {
            print('Web sign-in error: $e');
            if (e.toString().contains('popup_closed_by_user')) {
              return AuthResult(
                success: false,
                message: 'Sign in cancelled by user',
              );
            }
            return AuthResult(
              success: false,
              message: 'Web sign-in failed: $e',
            );
          }
        }
      } else {
        // Mobile platform - use normal sign in
        googleUser = await _googleSignIn!.signIn();
      }

      if (googleUser == null) {
        _updateAuthStatus(AuthStatus.unauthenticated);
        return AuthResult(
          success: false,
          message: 'Google sign-in cancelled',
        );
      }

      print('Google sign in successful for: ${googleUser.email}');

      // Step 2: Get Google auth details
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      if (googleAuth.accessToken == null && googleAuth.idToken == null) {
        _updateAuthStatus(AuthStatus.error);
        return AuthResult(
          success: false,
          message: 'Failed to get Google authentication tokens',
        );
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Step 3: Sign in to Firebase with Google credential
      print('Signing in to Firebase with Google credential');
      UserCredential firebaseCredential = await _auth.signInWithCredential(credential);
      User? firebaseUser = firebaseCredential.user;
      
      if (firebaseUser == null) {
        _updateAuthStatus(AuthStatus.error);
        return AuthResult(
          success: false,
          message: 'Failed to sign in with Google',
        );
      }
      
      print('Firebase sign in successful for: ${firebaseUser.email}');
      
      return AuthResult(
        success: true,
        message: 'Google sign-in successful',
      );
      
    } catch (e) {
      // Suppress known Pigeon type cast errors from google_sign_in plugin
      if (!e.toString().contains('PigeonUserDetails')) {
        print('Google sign-in error: $e');
        _updateAuthStatus(AuthStatus.error);

        return AuthResult(
          success: false,
          message: 'Google sign-in failed: $e',
        );
      }
      // If it's the known Pigeon error, just ignore it - auth already succeeded
      return AuthResult(success: true, message: 'Google sign-in completed');
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      print('Signing out user');
      _updateAuthStatus(AuthStatus.loading);

      // Sign out from Google if it was initialized
      if (_googleSignIn != null) {
        await _googleSignIn!.signOut();
      }

      // Sign out from Firebase
      await _auth.signOut();
      
      // Clear current user data
      _updateUser(null);
      _updateAuthStatus(AuthStatus.unauthenticated);
      
      print('User signed out successfully');
      
    } catch (e) {
      print('Error signing out: $e');
      _updateAuthStatus(AuthStatus.error);
    }
  }

  // Update user profile
  Future<bool> updateUserProfile({
    String? displayName,
    String? photoUrl,
    Map<String, dynamic>? preferences,
  }) async {
    try {
      if (_currentUser == null) {
        print('No current user to update');
        return false;
      }
      
      // Update Firebase profile if needed
      if (displayName != null || photoUrl != null) {
        await _auth.currentUser?.updateDisplayName(displayName);
        await _auth.currentUser?.updatePhotoURL(photoUrl);
      }
      
      // Update local user model
      UserModel updatedUser = _currentUser!.copyWith(
        displayName: displayName ?? _currentUser!.displayName,
        photoUrl: photoUrl ?? _currentUser!.photoUrl,
        preferences: preferences ?? _currentUser!.preferences,
      );
      
      // Save updated user via SyncService
      UserRegistrationResult result = await _syncService.registerUser(updatedUser);
      
      if (result.success) {
        _updateUser(updatedUser);
        print('User profile updated successfully');
        return true;
      } else {
        print('Failed to update user profile: ${result.message}');
        return false;
      }
      
    } catch (e) {
      print('Error updating user profile: $e');
      return false;
    }
  }

  // Update current user and notify listeners
  void _updateUser(UserModel? user) {
    if (_currentUser?.uid != user?.uid) { // Only update if user actually changed
      _currentUser = user;
      _userController.add(user);
    }
  }
  
  // Update auth status and notify listeners
  void _updateAuthStatus(AuthStatus status) {
    if (_currentAuthStatus != status) { // Only update if status actually changed
      _currentAuthStatus = status;
      _authStatusController.add(status);
    }
  }
  
  // Map sync status to auth status
  AuthStatus _mapSyncToAuthStatus(SyncStatus syncStatus) {
    switch (syncStatus) {
      case SyncStatus.syncing:
        return _currentUser != null ? AuthStatus.authenticated : AuthStatus.loading;
      case SyncStatus.synced:
        return _currentUser != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      case SyncStatus.pending:
        return _currentUser != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
      case SyncStatus.error:
        return _currentUser != null ? AuthStatus.authenticated : AuthStatus.error;
    }
  }
  
  // Get user-friendly error messages for Firebase errors
  String _getFirebaseErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
  
  // Check if user is currently authenticated
  bool get isAuthenticated => _currentUser != null && _currentAuthStatus == AuthStatus.authenticated;
  
  // Force refresh user data
  Future<void> refreshUserData() async {
    if (_auth.currentUser != null) {
      final firebaseUser = _auth.currentUser!;
      final userModel = UserModel(
        uid: firebaseUser.uid,
        email: firebaseUser.email ?? '',
        displayName: firebaseUser.displayName,
        photoUrl: firebaseUser.photoURL,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
        isEmailVerified: firebaseUser.emailVerified,
      );
      
      _currentUser = userModel;
      _userController.add(userModel);
      await _handleUserLogin(firebaseUser.uid);
    }
  }
  
  // Dispose resources
  void dispose() {
    _authStateSubscription?.cancel();
    _userController.close();
    _authStatusController.close();
    _syncService.dispose();
  }
}