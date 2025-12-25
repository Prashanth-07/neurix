import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/user_model.dart';
import 'local_db_service.dart';
import 'cloud_db_service.dart';

enum SyncStatus {
  synced,    // Data is synchronized
  syncing,   // Currently syncing
  pending,   // Waiting to sync (offline)
  error,     // Sync failed
}

enum DataSource {
  local,     // Data came from local database
  cloud,     // Data came from cloud database
  both,      // Data was merged from both sources
}

class UserRegistrationResult {
  final bool success;
  final bool localSaved;
  final bool cloudSaved;
  final String message;
  final UserModel? user;
  
  UserRegistrationResult({
    required this.success,
    required this.localSaved,
    required this.cloudSaved,
    required this.message,
    this.user,
  });
  
  @override
  String toString() {
    return 'UserRegistrationResult(success: $success, localSaved: $localSaved, cloudSaved: $cloudSaved, message: $message)';
  }
}

class UserLoginResult {
  final bool success;
  final UserModel? user;
  final DataSource? source;
  final String message;
  
  UserLoginResult({
    required this.success,
    this.user,
    this.source,
    required this.message,
  });
  
  @override
  String toString() {
    return 'UserLoginResult(success: $success, source: $source, message: $message)';
  }
}

class SyncService {
  static final LocalDbService _localDb = LocalDbService();
  static final CloudDbService _cloudDb = CloudDbService();
  
  // Stream controllers for connectivity and sync status
  final StreamController<bool> _connectivityController = StreamController<bool>.broadcast();
  final StreamController<SyncStatus> _syncStatusController = StreamController<SyncStatus>.broadcast();
  
  // Getters for streams
  Stream<bool> get connectivityStream => _connectivityController.stream;
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;
  
  // Current sync status
  SyncStatus _currentSyncStatus = SyncStatus.synced;
  
  // Add retry tracking
  static const int _maxRetries = 3;
  int _currentRetries = 0;
  DateTime? _lastRetryAttempt;
  static const Duration _retryDelay = Duration(seconds: 5);

  // Initialize sync service and start monitoring connectivity
  Future<void> initialize() async {
    print('Initializing SyncService...');
    
    // Reset retry counters
    _currentRetries = 0;
    _lastRetryAttempt = null;
    
    // Start monitoring connectivity changes
    _startConnectivityMonitoring();
    
    // Check initial connectivity status
    bool isOnline = await _cloudDb.isOnline();
    _connectivityController.add(isOnline);
    
    print('SyncService initialized. Online: $isOnline');
  }

  // Start monitoring connectivity changes
  void _startConnectivityMonitoring() {
    Connectivity().onConnectivityChanged.listen((ConnectivityResult result) async {
      bool isOnline = result != ConnectivityResult.none;
      print('Connectivity changed: $isOnline');
      _connectivityController.add(isOnline);
      
      // Reset retry counters when connectivity changes
      if (isOnline) {
        _currentRetries = 0;
        _lastRetryAttempt = null;
        await _syncPendingData();
      }
    });
  }

  // Register user with hybrid approach (local first, then cloud)
  Future<UserRegistrationResult> registerUser(UserModel user) async {
    print('Starting user registration for: ${user.email}');
    _updateSyncStatus(SyncStatus.syncing);
    
    try {
      // Step 1: Always save to local database first (for offline capability)
      bool localSaved = await _localDb.saveUser(user);
      
      if (!localSaved) {
        _updateSyncStatus(SyncStatus.error);
        return UserRegistrationResult(
          success: false,
          localSaved: false,
          cloudSaved: false,
          message: 'Failed to save user locally',
        );
      }
      
      print('User saved to local database successfully');
      
      // Step 2: Try to save to cloud if online
      bool cloudSaved = false;
      bool isOnline = await _cloudDb.isOnline();
      
      if (isOnline) {
        print('Device is online, attempting cloud save...');
        cloudSaved = await _tryCloudOperation(() => _cloudDb.saveUser(user));
        
        if (cloudSaved) {
          print('User saved to cloud database successfully');
          _updateSyncStatus(SyncStatus.synced);
          _currentRetries = 0; // Reset retry counter on success
        } else {
          print('Failed to save to cloud, but local save succeeded');
          _updateSyncStatus(SyncStatus.pending);
        }
      } else {
        print('Device is offline, cloud save skipped');
        _updateSyncStatus(SyncStatus.pending);
      }
      
      return UserRegistrationResult(
        success: true,
        localSaved: localSaved,
        cloudSaved: cloudSaved,
        message: cloudSaved 
            ? 'User registered successfully and synced to cloud'
            : 'User registered locally, will sync when online',
        user: user,
      );
      
    } catch (e) {
      print('Error during user registration: $e');
      _updateSyncStatus(SyncStatus.error);
      
      return UserRegistrationResult(
        success: false,
        localSaved: false,
        cloudSaved: false,
        message: 'Registration failed: $e',
      );
    }
  }

  // Helper method for retrying cloud operations
  Future<T> _tryCloudOperation<T>(Future<T> Function() operation) async {
    if (_currentRetries >= _maxRetries) {
      // Check if enough time has passed since last retry
      if (_lastRetryAttempt != null && 
          DateTime.now().difference(_lastRetryAttempt!) < _retryDelay) {
        print('Too many retry attempts, waiting before trying again');
        return Future.error('Too many retry attempts');
      }
      // Reset counter after delay
      _currentRetries = 0;
    }

    try {
      _currentRetries++;
      _lastRetryAttempt = DateTime.now();
      return await operation();
    } catch (e) {
      print('Cloud operation failed (attempt $_currentRetries): $e');
      if (_currentRetries < _maxRetries) {
        // Wait before retrying
        await Future.delayed(_retryDelay);
        return _tryCloudOperation(operation);
      }
      rethrow;
    }
  }

  // Login user with hybrid approach (local first, sync in background)
  Future<UserLoginResult> loginUser(String uid) async {
    print('Starting user login for UID: $uid');
    _updateSyncStatus(SyncStatus.syncing);
    
    try {
      // Step 1: Always try to get user from local database first (fast)
      UserModel? localUser = await _localDb.getUserByUid(uid);
      
      if (localUser == null) {
        print('No user found in local database');
        
        // Try cloud if online
        bool isOnline = await _cloudDb.isOnline();
        if (isOnline) {
          print('Trying to fetch user from cloud...');
          UserModel? cloudUser = await _cloudDb.getUserByUid(uid);
          
          if (cloudUser != null) {
            // Save cloud user to local database for future offline access
            await _localDb.saveUser(cloudUser);
            await _localDb.updateLastLogin(uid);
            _updateSyncStatus(SyncStatus.synced);
            
            return UserLoginResult(
              success: true,
              user: cloudUser,
              source: DataSource.cloud,
              message: 'User loaded from cloud and cached locally',
            );
          }
        }
        
        _updateSyncStatus(SyncStatus.error);
        return UserLoginResult(
          success: false,
          message: 'User not found in local or cloud database',
        );
      }
      
      print('User found in local database: ${localUser.email}');
      
      // Step 2: Update last login in local database
      await _localDb.updateLastLogin(uid);
      
      // Step 3: Try to sync with cloud in background (don't wait for it)
      _backgroundSyncUser(uid);
      
      _updateSyncStatus(SyncStatus.synced);
      
      return UserLoginResult(
        success: true,
        user: localUser,
        source: DataSource.local,
        message: 'User logged in successfully',
      );
      
    } catch (e) {
      print('Error during user login: $e');
      _updateSyncStatus(SyncStatus.error);
      
      return UserLoginResult(
        success: false,
        message: 'Login failed: $e',
      );
    }
  }

  // Sync user data in background
  Future<void> _backgroundSyncUser(String uid) async {
    Future.microtask(() async {
      try {
        bool isOnline = await _cloudDb.isOnline();
        if (!isOnline) {
          print('Device offline, skipping background sync');
          return;
        }
        
        print('Starting background sync for user: $uid');
        
        // Get data from both sources
        UserModel? localUser = await _localDb.getUserByUid(uid);
        UserModel? cloudUser = await _cloudDb.getUserByUid(uid);
        
        if (localUser == null) {
          print('No local user found during background sync');
          return;
        }
        
        // If no cloud user exists, upload local user
        if (cloudUser == null) {
          print('No cloud user found, uploading local user...');
          await _cloudDb.saveUser(localUser);
          await _cloudDb.updateLastLogin(uid);
          return;
        }
        
        // Compare timestamps to determine which is more recent
        bool localNewer = localUser.lastLoginAt != null && 
            cloudUser.lastLoginAt != null &&
            localUser.lastLoginAt!.isAfter(cloudUser.lastLoginAt!);
        
        if (localNewer) {
          print('Local user is newer, updating cloud...');
          await _cloudDb.saveUser(localUser);
        } else {
          print('Cloud user is newer, updating local...');
          await _localDb.saveUser(cloudUser);
        }
        
        // Always update last login in cloud
        await _cloudDb.updateLastLogin(uid);
        
        print('Background sync completed successfully');
        
      } catch (e) {
        print('Error during background sync: $e');
      }
    });
  }

  // Sync all pending data when connection is restored
  Future<void> _syncPendingData() async {
    try {
      print('Syncing pending data...');
      _updateSyncStatus(SyncStatus.syncing);
      
      // Get all users from local database
      List<UserModel> localUsers = await _localDb.getAllUsers();
      
      int syncedCount = 0;
      for (UserModel user in localUsers) {
        bool cloudSaved = await _cloudDb.saveUser(user);
        if (cloudSaved) {
          syncedCount++;
        }
      }
      
      print('Synced $syncedCount out of ${localUsers.length} users');
      _updateSyncStatus(SyncStatus.synced);
      
    } catch (e) {
      print('Error syncing pending data: $e');
      _updateSyncStatus(SyncStatus.error);
    }
  }

  // Update sync status and notify listeners
  void _updateSyncStatus(SyncStatus status) {
    _currentSyncStatus = status;
    _syncStatusController.add(status);
    print('Sync status updated: $status');
  }
  
  // Get current sync status
  SyncStatus get currentSyncStatus => _currentSyncStatus;
  
  // Force sync now (manual sync)
  Future<bool> forceSyncNow() async {
    print('Force sync requested...');
    
    bool isOnline = await _cloudDb.isOnline();
    if (!isOnline) {
      print('Cannot force sync: device is offline');
      return false;
    }
    
    await _syncPendingData();
    return true;
  }
  
  // Get user from either source (smart selection)
  Future<UserModel?> getUser(String uid) async {
    // Try local first (fast)
    UserModel? user = await _localDb.getUserByUid(uid);
    
    if (user != null) {
      // Start background sync but don't wait for it
      _backgroundSyncUser(uid);
      return user;
    }
    
    // Try cloud if local not found and online
    bool isOnline = await _cloudDb.isOnline();
    if (isOnline) {
      user = await _cloudDb.getUserByUid(uid);
      if (user != null) {
        // Cache in local database
        await _localDb.saveUser(user);
      }
    }
    
    return user;
  }
  
  // Clear all local data (for debugging/logout)
  Future<void> clearLocalData() async {
    await _localDb.clearAllData();
    print('All local data cleared');
  }
  
  // Dispose resources
  void dispose() {
    _connectivityController.close();
    _syncStatusController.close();
  }

  Future<void> sync() async {
    try {
      if (_currentSyncStatus == SyncStatus.syncing) {
        print('Sync already in progress, skipping...');
        return;
      }

      _updateSyncStatus(SyncStatus.syncing);
      
      bool isOnline = await _cloudDb.isOnline();
      if (!isOnline) {
        print('No internet connection, skipping sync');
        _updateSyncStatus(SyncStatus.pending);
        return;
      }

      // Add retry count to prevent infinite loops
      int retryCount = 0;
      const maxRetries = 3;

      while (retryCount < maxRetries) {
        try {
          await _performSync();
          _updateSyncStatus(SyncStatus.synced);
          return;
        } catch (e) {
          print('Sync attempt ${retryCount + 1} failed: $e');
          retryCount++;
          if (retryCount >= maxRetries) {
            _updateSyncStatus(SyncStatus.error);
            print('Max retry attempts reached, sync failed');
            return;
          }
          // Wait before retrying
          await Future.delayed(Duration(seconds: 2));
        }
      }
    } catch (e) {
      print('Sync error: $e');
      _updateSyncStatus(SyncStatus.error);
    }
  }

  Future<void> _performSync() async {
    // Implementation of _performSync method
  }
} 