import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/user_model.dart';

class LocalDbService {
  static Database? _database;
  static const String _databaseName = 'neurix.db';
  static const int _databaseVersion = 1;
  
  // Table names
  static const String _usersTable = 'users';
  static const String _memoriesTable = 'memories'; // For future use
  
  // Get database instance
  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on web platform');
    }
    
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Initialize database
  Future<Database> _initDatabase() async {
    try {
      String path = join(await getDatabasesPath(), _databaseName);
      
      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _createTables,
      );
    } catch (e) {
      print('Error initializing database: $e');
      rethrow;
    }
  }

  // Create database tables
  Future<void> _createTables(Database db, int version) async {
    try {
      await db.execute('''
        CREATE TABLE $_usersTable (
          uid TEXT PRIMARY KEY,
          email TEXT UNIQUE NOT NULL,
          display_name TEXT,
          photo_url TEXT,
          created_at TEXT NOT NULL,
          last_login_at TEXT,
          is_email_verified INTEGER DEFAULT 0,
          preferences TEXT
        )
      ''');

      print('Database tables created successfully');
    } catch (e) {
      print('Error creating tables: $e');
      rethrow;
    }
  }

  // Save user to local database
  Future<bool> saveUser(UserModel user) async {
    try {
      if (kIsWeb) {
        print('Web platform: Skipping local database');
        return true;
      }
      
      final db = await database;
      
      Map<String, dynamic> userMap = user.toMap();
      if (user.preferences != null) {
        userMap['preferences'] = jsonEncode(user.preferences);
      }
      
      await db.insert(
        _usersTable,
        userMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      print('User saved to local database: ${user.email}');
      return true;
    } catch (e) {
      print('Error saving user to local database: $e');
      return false;
    }
  }

  // Get user by UID from local database
  Future<UserModel?> getUserByUid(String uid) async {
    try {
      if (kIsWeb) {
        print('Web platform: Local database not available');
        return null;
      }
      
      final db = await database;
      
      final List<Map<String, dynamic>> maps = await db.query(
        _usersTable,
        where: 'uid = ?',
        whereArgs: [uid],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        Map<String, dynamic> userMap = Map.from(maps.first);
        
        if (userMap['preferences'] != null) {
          try {
            userMap['preferences'] = jsonDecode(userMap['preferences']);
          } catch (e) {
            userMap['preferences'] = {};
          }
        }
        
        UserModel user = UserModel.fromMap(userMap);
        print('User retrieved from local database: ${user.email}');
        return user;
      }
      
      print('No user found in local database with UID: $uid');
      return null;
    } catch (e) {
      print('Error getting user from local database: $e');
      return null;
    }
  }

  // Get all users from local database
  Future<List<UserModel>> getAllUsers() async {
    try {
      if (kIsWeb) {
        return [];
      }
      
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(_usersTable);
      
      return maps.map((map) {
        if (map['preferences'] != null) {
          try {
            map['preferences'] = jsonDecode(map['preferences']);
          } catch (e) {
            map['preferences'] = {};
          }
        }
        return UserModel.fromMap(map);
      }).toList();
    } catch (e) {
      print('Error getting all users: $e');
      return [];
    }
  }

  // Update user's last login time
  Future<bool> updateLastLogin(String uid) async {
    try {
      if (kIsWeb) {
        print('Web platform: Skipping local database update');
        return true;
      }
      
      final db = await database;
      
      await db.update(
        _usersTable,
        {'last_login_at': DateTime.now().toIso8601String()},
        where: 'uid = ?',
        whereArgs: [uid],
      );
      
      print('Updated last login in local database for user: $uid');
      return true;
    } catch (e) {
      print('Error updating last login in local database: $e');
      return false;
    }
  }

  // Clear all data
  Future<bool> clearAllData() async {
    try {
      if (kIsWeb) {
        print('Web platform: No local data to clear');
        return true;
      }
      
      final db = await database;
      await db.delete(_usersTable);
      await db.delete(_memoriesTable);
      print('All local data cleared');
      return true;
    } catch (e) {
      print('Error clearing data: $e');
      return false;
    }
  }

  // Close database connection
  Future<void> close() async {
    final db = _database;
    if (db != null && !kIsWeb) {
      await db.close();
      _database = null;
    }
  }
} 