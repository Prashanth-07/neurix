import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/user_model.dart';

class CloudDbService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Collection names
  static const String _usersCollection = 'users';
  static const String _memoriesCollection = 'memories'; // For future use
  
  // Check if device is online
  Future<bool> isOnline() async {
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      bool isConnected = connectivityResult != ConnectivityResult.none;
      print('Device connectivity status: $isConnected');
      return isConnected;
    } catch (e) {
      print('Error checking connectivity: $e');
      return false;
    }
  }

  // Save user to Firestore
  Future<bool> saveUser(UserModel user) async {
    try {
      if (!await isOnline()) {
        print('Device is offline, skipping Firestore save');
        return false;
      }

      Map<String, dynamic> userData = user.toFirestore();
      
      await _firestore
          .collection(_usersCollection)
          .doc(user.uid)
          .set(userData, SetOptions(merge: true));
      
      print('User saved to Firestore: ${user.email}');
      return true;
    } catch (e) {
      print('Error saving user to Firestore: $e');
      return false;
    }
  }

  // Get user from Firestore by UID
  Future<UserModel?> getUserByUid(String uid) async {
    try {
      if (!await isOnline()) {
        print('Device is offline, cannot fetch from Firestore');
        return null;
      }

      DocumentSnapshot doc = await _firestore
          .collection(_usersCollection)
          .doc(uid)
          .get();

      if (doc.exists && doc.data() != null) {
        Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;
        UserModel user = UserModel.fromFirestore(userData);
        print('User retrieved from Firestore: ${user.email}');
        return user;
      }
      
      print('No user found in Firestore with UID: $uid');
      return null;
    } catch (e) {
      print('Error getting user from Firestore: $e');
      return null;
    }
  }

  // Get user from Firestore by email
  Future<UserModel?> getUserByEmail(String email) async {
    try {
      if (!await isOnline()) {
        print('Device is offline, cannot fetch from Firestore');
        return null;
      }

      QuerySnapshot querySnapshot = await _firestore
          .collection(_usersCollection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        DocumentSnapshot doc = querySnapshot.docs.first;
        Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;
        UserModel user = UserModel.fromFirestore(userData);
        print('User retrieved from Firestore by email: ${user.email}');
        return user;
      } else {
        print('No user found in Firestore with email: $email');
        return null;
      }
    } on FirebaseException catch (e) {
      print('Firebase error getting user by email: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('Error getting user by email from Firestore: $e');
      return null;
    }
  }

  // Update user's last login time
  Future<bool> updateLastLogin(String uid) async {
    try {
      if (!await isOnline()) {
        print('Device is offline, skipping Firestore update');
        return false;
      }

      await _firestore
          .collection(_usersCollection)
          .doc(uid)
          .update({
        'lastLoginAt': FieldValue.serverTimestamp(),
      });

      print('Updated last login in Firestore for user: $uid');
      return true;
    } catch (e) {
      print('Error updating last login: $e');
      return false;
    }
  }

  // Update user preferences in Firestore
  Future<bool> updateUserPreferences(String uid, Map<String, dynamic> preferences) async {
    try {
      if (!await isOnline()) {
        print('Device is offline, skipping Firestore preferences update');
        return false;
      }

      await _firestore
          .collection(_usersCollection)
          .doc(uid)
          .update({
        'preferences': preferences,
      });

      print('Updated user preferences in Firestore for user: $uid');
      return true;
    } on FirebaseException catch (e) {
      print('Firebase error updating preferences: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('Error updating preferences in Firestore: $e');
      return false;
    }
  }

  // Delete user from Firestore
  Future<bool> deleteUser(String uid) async {
    try {
      if (!await isOnline()) {
        print('Device is offline, cannot delete from Firestore');
        return false;
      }

      await _firestore
          .collection(_usersCollection)
          .doc(uid)
          .delete();

      print('User deleted from Firestore: $uid');
      return true;
    } on FirebaseException catch (e) {
      print('Firebase error deleting user: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      print('Error deleting user from Firestore: $e');
      return false;
    }
  }

  // Check if user exists in Firestore
  Future<bool> userExistsInFirestore(String uid) async {
    try {
      if (!await isOnline()) return false;
      
      DocumentSnapshot doc = await _firestore
          .collection(_usersCollection)
          .doc(uid)
          .get();
      
      return doc.exists;
    } catch (e) {
      print('Error checking if user exists in Firestore: $e');
      return false;
    }
  }

  // Get the last updated timestamp for a user
  Future<DateTime?> getUserLastUpdated(String uid) async {
    try {
      if (!await isOnline()) return null;
      
      DocumentSnapshot doc = await _firestore
          .collection(_usersCollection)
          .doc(uid)
          .get();
      
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        if (data['lastLoginAt'] != null) {
          return (data['lastLoginAt'] as Timestamp).toDate();
        }
      }
      return null;
    } catch (e) {
      print('Error getting user last updated: $e');
      return null;
    }
  }

  // Listen to user changes in real-time
  Stream<UserModel?> getUserStream(String uid) {
    return _firestore
        .collection(_usersCollection)
        .doc(uid)
        .snapshots()
        .map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return UserModel.fromFirestore(snapshot.data() as Map<String, dynamic>);
      }
      return null;
    });
  }

  // Test Firestore connection
  Future<bool> testConnection() async {
    try {
      if (!await isOnline()) return false;
      
      await _firestore
          .collection('test')
          .limit(1)
          .get();
      
      print('Firestore connection test successful');
      return true;
    } catch (e) {
      print('Firestore connection test failed: $e');
      return false;
    }
  }
} 