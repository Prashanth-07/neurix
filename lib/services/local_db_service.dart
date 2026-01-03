import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/user_model.dart';
import '../models/memory_model.dart';
import '../models/reminder_model.dart';
import 'embedding_service.dart';

class LocalDbService {
  static Database? _database;
  static const String _databaseName = 'neurix.db';
  static const int _databaseVersion = 3; // Bumped version to add reminders table

  // Table names
  static const String _usersTable = 'users';
  static const String _memoriesTable = 'memories';
  static const String _remindersTable = 'reminders';
  
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
        onUpgrade: _onUpgrade,
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

      await db.execute('''
        CREATE TABLE $_memoriesTable (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          embedding TEXT,
          metadata TEXT
        )
      ''');

      // Create index for faster user-based queries
      await db.execute('''
        CREATE INDEX idx_memories_user_id ON $_memoriesTable(user_id)
      ''');

      await db.execute('''
        CREATE TABLE $_remindersTable (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          message TEXT NOT NULL,
          type TEXT NOT NULL,
          interval_minutes INTEGER,
          scheduled_time TEXT,
          next_trigger TEXT NOT NULL,
          is_active INTEGER DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');

      // Create index for faster reminder queries
      await db.execute('''
        CREATE INDEX idx_reminders_user_id ON $_remindersTable(user_id)
      ''');

      await db.execute('''
        CREATE INDEX idx_reminders_next_trigger ON $_remindersTable(next_trigger)
      ''');

      print('Database tables created successfully');
    } catch (e) {
      print('Error creating tables: $e');
      rethrow;
    }
  }

  // Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add memories table for version 2
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_memoriesTable (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          embedding TEXT,
          metadata TEXT
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_memories_user_id ON $_memoriesTable(user_id)
      ''');

      print('Database upgraded to version 2');
    }

    if (oldVersion < 3) {
      // Add reminders table for version 3
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_remindersTable (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          message TEXT NOT NULL,
          type TEXT NOT NULL,
          interval_minutes INTEGER,
          scheduled_time TEXT,
          next_trigger TEXT NOT NULL,
          is_active INTEGER DEFAULT 1,
          created_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_reminders_user_id ON $_remindersTable(user_id)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_reminders_next_trigger ON $_remindersTable(next_trigger)
      ''');

      print('Database upgraded to version 3');
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

  // ==================== MEMORY OPERATIONS ====================

  // Save memory to local database
  Future<bool> saveMemory(Memory memory) async {
    try {
      if (kIsWeb) {
        print('Web platform: Skipping local database');
        return true;
      }

      final db = await database;

      await db.insert(
        _memoriesTable,
        memory.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('Memory saved to local database: ${memory.id}');
      return true;
    } catch (e) {
      print('Error saving memory to local database: $e');
      return false;
    }
  }

  // Get all memories for a user
  Future<List<Memory>> getMemoriesByUserId(String userId) async {
    try {
      if (kIsWeb) {
        return [];
      }

      final db = await database;

      final List<Map<String, dynamic>> maps = await db.query(
        _memoriesTable,
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'created_at DESC',
      );

      print('Retrieved ${maps.length} memories for user: $userId');
      return maps.map((map) => Memory.fromMap(map)).toList();
    } catch (e) {
      print('Error getting memories from local database: $e');
      return [];
    }
  }

  // Get a single memory by ID
  Future<Memory?> getMemoryById(String memoryId) async {
    try {
      if (kIsWeb) {
        return null;
      }

      final db = await database;

      final List<Map<String, dynamic>> maps = await db.query(
        _memoriesTable,
        where: 'id = ?',
        whereArgs: [memoryId],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return Memory.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      print('Error getting memory by ID: $e');
      return null;
    }
  }

  // Search memories by content (keyword-based search)
  Future<List<Memory>> searchMemories(String userId, String query) async {
    try {
      if (kIsWeb) {
        return [];
      }

      final db = await database;

      // Extract meaningful keywords from the query (ignore common words)
      final stopWords = {
        'i', 'me', 'my', 'we', 'our', 'you', 'your', 'the', 'a', 'an', 'is',
        'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
        'do', 'does', 'did', 'will', 'would', 'could', 'should', 'may',
        'might', 'must', 'shall', 'can', 'need', 'dare', 'ought', 'used',
        'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'from', 'as',
        'into', 'through', 'during', 'before', 'after', 'above', 'below',
        'between', 'under', 'again', 'further', 'then', 'once', 'here',
        'there', 'when', 'where', 'why', 'how', 'all', 'each', 'few',
        'more', 'most', 'other', 'some', 'such', 'no', 'nor', 'not',
        'only', 'own', 'same', 'so', 'than', 'too', 'very', 'just',
        'and', 'but', 'if', 'or', 'because', 'until', 'while', 'of',
        'about', 'against', 'what', 'which', 'who', 'whom', 'this',
        'that', 'these', 'those', 'am', 'tell', 'told', 'know', 'remember',
      };

      final keywords = query
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '') // Remove punctuation
          .split(RegExp(r'\s+'))
          .where((word) => word.length > 2 && !stopWords.contains(word))
          .toSet()
          .toList();

      print('Search keywords extracted: $keywords');

      if (keywords.isEmpty) {
        // If no meaningful keywords, return all memories for user
        final List<Map<String, dynamic>> maps = await db.query(
          _memoriesTable,
          where: 'user_id = ?',
          whereArgs: [userId],
          orderBy: 'created_at DESC',
        );
        print('No keywords found, returning all ${maps.length} memories');
        return maps.map((map) => Memory.fromMap(map)).toList();
      }

      // Build a query that matches ANY of the keywords
      final whereClauses = keywords.map((_) => 'LOWER(content) LIKE ?').join(' OR ');
      final whereArgs = [userId, ...keywords.map((k) => '%$k%')];

      final List<Map<String, dynamic>> maps = await db.rawQuery(
        'SELECT * FROM $_memoriesTable WHERE user_id = ? AND ($whereClauses) ORDER BY created_at DESC',
        whereArgs,
      );

      print('Found ${maps.length} memories matching keywords: $keywords');
      return maps.map((map) => Memory.fromMap(map)).toList();
    } catch (e) {
      print('Error searching memories: $e');
      return [];
    }
  }

  // Semantic search using embeddings and cosine similarity
  Future<List<Memory>> semanticSearchMemories(
    String userId,
    List<double> queryEmbedding, {
    int topK = 5,
    double similarityThreshold = 0.3,
  }) async {
    try {
      if (kIsWeb) {
        return [];
      }

      final db = await database;
      final embeddingService = EmbeddingService();

      // Get all memories for the user that have embeddings
      final List<Map<String, dynamic>> maps = await db.query(
        _memoriesTable,
        where: 'user_id = ? AND embedding IS NOT NULL',
        whereArgs: [userId],
      );

      print('Found ${maps.length} memories with embeddings for semantic search');

      if (maps.isEmpty) {
        print('No memories with embeddings found, falling back to keyword search');
        return [];
      }

      // Convert to MemoryWithEmbedding objects
      List<MemoryWithEmbedding> memoriesWithEmbeddings = [];
      for (var map in maps) {
        List<double>? embedding;
        if (map['embedding'] != null) {
          try {
            final embeddingData = jsonDecode(map['embedding']);
            embedding = (embeddingData as List).cast<double>();
          } catch (e) {
            print('Error parsing embedding for memory ${map['id']}: $e');
            continue;
          }
        }

        if (embedding != null && embedding.isNotEmpty) {
          memoriesWithEmbeddings.add(MemoryWithEmbedding(
            id: map['id'],
            content: map['content'],
            createdAt: DateTime.parse(map['created_at']),
            embedding: embedding,
          ));
        }
      }

      print('Parsed ${memoriesWithEmbeddings.length} memories with valid embeddings');

      // Use embedding service to find similar memories
      List<ScoredMemory> scoredResults = embeddingService.searchSimilar(
        queryEmbedding: queryEmbedding,
        memories: memoriesWithEmbeddings,
        topK: topK,
        similarityThreshold: similarityThreshold,
      );

      print('Semantic search found ${scoredResults.length} relevant memories');
      for (var result in scoredResults) {
        print('  - ${result.content.substring(0, result.content.length > 50 ? 50 : result.content.length)}... (score: ${result.finalScore.toStringAsFixed(3)})');
      }

      // Convert back to Memory objects
      List<Memory> results = [];
      for (var scored in scoredResults) {
        results.add(Memory(
          id: scored.memoryId,
          userId: userId,
          content: scored.content,
          createdAt: scored.createdAt,
        ));
      }

      return results;
    } catch (e) {
      print('Error in semantic search: $e');
      return [];
    }
  }

  // Get memories that don't have embeddings (for batch processing)
  Future<List<Memory>> getMemoriesWithoutEmbeddings(String userId) async {
    try {
      if (kIsWeb) {
        return [];
      }

      final db = await database;

      final List<Map<String, dynamic>> maps = await db.query(
        _memoriesTable,
        where: 'user_id = ? AND (embedding IS NULL OR embedding = "")',
        whereArgs: [userId],
        orderBy: 'created_at DESC',
      );

      print('Found ${maps.length} memories without embeddings');
      return maps.map((map) => Memory.fromMap(map)).toList();
    } catch (e) {
      print('Error getting memories without embeddings: $e');
      return [];
    }
  }

  // Update memory with embedding
  Future<bool> updateMemoryEmbedding(String memoryId, List<double> embedding) async {
    try {
      if (kIsWeb) {
        return true;
      }

      final db = await database;

      await db.update(
        _memoriesTable,
        {'embedding': jsonEncode(embedding)},
        where: 'id = ?',
        whereArgs: [memoryId],
      );

      print('Updated embedding for memory: $memoryId');
      return true;
    } catch (e) {
      print('Error updating memory embedding: $e');
      return false;
    }
  }

  // Delete a memory
  Future<bool> deleteMemory(String memoryId) async {
    try {
      if (kIsWeb) {
        return true;
      }

      final db = await database;

      await db.delete(
        _memoriesTable,
        where: 'id = ?',
        whereArgs: [memoryId],
      );

      print('Memory deleted: $memoryId');
      return true;
    } catch (e) {
      print('Error deleting memory: $e');
      return false;
    }
  }

  // Delete all memories for a user
  Future<bool> deleteAllMemoriesForUser(String userId) async {
    try {
      if (kIsWeb) {
        return true;
      }

      final db = await database;

      final count = await db.delete(
        _memoriesTable,
        where: 'user_id = ?',
        whereArgs: [userId],
      );

      print('Deleted $count memories for user: $userId');
      return true;
    } catch (e) {
      print('Error deleting user memories: $e');
      return false;
    }
  }

  // Get memory count for a user
  Future<int> getMemoryCount(String userId) async {
    try {
      if (kIsWeb) {
        return 0;
      }

      final db = await database;

      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_memoriesTable WHERE user_id = ?',
        [userId],
      );

      return result.first['count'] as int? ?? 0;
    } catch (e) {
      print('Error getting memory count: $e');
      return 0;
    }
  }

  // ==================== END MEMORY OPERATIONS ====================

  // ==================== REMINDER OPERATIONS ====================

  // Save reminder to local database
  Future<bool> saveReminder(Reminder reminder) async {
    try {
      if (kIsWeb) {
        print('Web platform: Skipping local database');
        return true;
      }

      final db = await database;

      await db.insert(
        _remindersTable,
        reminder.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      print('Reminder saved to local database: ${reminder.id}');
      return true;
    } catch (e) {
      print('Error saving reminder to local database: $e');
      return false;
    }
  }

  // Get all reminders for a user
  Future<List<Reminder>> getRemindersByUserId(String userId) async {
    try {
      if (kIsWeb) {
        return [];
      }

      final db = await database;

      final List<Map<String, dynamic>> maps = await db.query(
        _remindersTable,
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'next_trigger ASC',
      );

      print('Retrieved ${maps.length} reminders for user: $userId');
      return maps.map((map) => Reminder.fromMap(map)).toList();
    } catch (e) {
      print('Error getting reminders from local database: $e');
      return [];
    }
  }

  // Get active reminders for a user
  Future<List<Reminder>> getActiveRemindersByUserId(String userId) async {
    try {
      if (kIsWeb) {
        return [];
      }

      final db = await database;

      final List<Map<String, dynamic>> maps = await db.query(
        _remindersTable,
        where: 'user_id = ? AND is_active = 1',
        whereArgs: [userId],
        orderBy: 'next_trigger ASC',
      );

      print('Retrieved ${maps.length} active reminders for user: $userId');
      return maps.map((map) => Reminder.fromMap(map)).toList();
    } catch (e) {
      print('Error getting active reminders: $e');
      return [];
    }
  }

  // Get all active reminders (for rescheduling on app start)
  Future<List<Reminder>> getAllActiveReminders() async {
    try {
      if (kIsWeb) {
        return [];
      }

      final db = await database;

      final List<Map<String, dynamic>> maps = await db.query(
        _remindersTable,
        where: 'is_active = 1',
        orderBy: 'next_trigger ASC',
      );

      print('Retrieved ${maps.length} total active reminders');
      return maps.map((map) => Reminder.fromMap(map)).toList();
    } catch (e) {
      print('Error getting all active reminders: $e');
      return [];
    }
  }

  // Get a single reminder by ID
  Future<Reminder?> getReminderById(String reminderId) async {
    try {
      if (kIsWeb) {
        return null;
      }

      final db = await database;

      final List<Map<String, dynamic>> maps = await db.query(
        _remindersTable,
        where: 'id = ?',
        whereArgs: [reminderId],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return Reminder.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      print('Error getting reminder by ID: $e');
      return null;
    }
  }

  // Find reminder by message (for duplicate detection)
  Future<Reminder?> findReminderByMessage(String userId, String message) async {
    try {
      if (kIsWeb) {
        return null;
      }

      final db = await database;

      // Search for reminders with similar message (case-insensitive)
      final List<Map<String, dynamic>> maps = await db.query(
        _remindersTable,
        where: 'user_id = ? AND LOWER(message) LIKE ? AND is_active = 1',
        whereArgs: [userId, '%${message.toLowerCase()}%'],
        limit: 1,
      );

      if (maps.isNotEmpty) {
        return Reminder.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      print('Error finding reminder by message: $e');
      return null;
    }
  }

  // Update reminder
  Future<bool> updateReminder(Reminder reminder) async {
    try {
      if (kIsWeb) {
        return true;
      }

      final db = await database;

      await db.update(
        _remindersTable,
        reminder.toMap(),
        where: 'id = ?',
        whereArgs: [reminder.id],
      );

      print('Reminder updated: ${reminder.id}');
      return true;
    } catch (e) {
      print('Error updating reminder: $e');
      return false;
    }
  }

  // Delete a reminder
  Future<bool> deleteReminder(String reminderId) async {
    try {
      if (kIsWeb) {
        return true;
      }

      final db = await database;

      await db.delete(
        _remindersTable,
        where: 'id = ?',
        whereArgs: [reminderId],
      );

      print('Reminder deleted: $reminderId');
      return true;
    } catch (e) {
      print('Error deleting reminder: $e');
      return false;
    }
  }

  // Delete all reminders for a user
  Future<bool> deleteAllRemindersForUser(String userId) async {
    try {
      if (kIsWeb) {
        return true;
      }

      final db = await database;

      final count = await db.delete(
        _remindersTable,
        where: 'user_id = ?',
        whereArgs: [userId],
      );

      print('Deleted $count reminders for user: $userId');
      return true;
    } catch (e) {
      print('Error deleting user reminders: $e');
      return false;
    }
  }

  // Get reminders that are due (next_trigger <= now)
  Future<List<Reminder>> getDueReminders() async {
    try {
      if (kIsWeb) {
        return [];
      }

      final db = await database;
      final now = DateTime.now().toIso8601String();

      final List<Map<String, dynamic>> maps = await db.query(
        _remindersTable,
        where: 'is_active = 1 AND next_trigger <= ?',
        whereArgs: [now],
        orderBy: 'next_trigger ASC',
      );

      print('Found ${maps.length} due reminders');
      return maps.map((map) => Reminder.fromMap(map)).toList();
    } catch (e) {
      print('Error getting due reminders: $e');
      return [];
    }
  }

  // Get reminder count for a user
  Future<int> getReminderCount(String userId) async {
    try {
      if (kIsWeb) {
        return 0;
      }

      final db = await database;

      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_remindersTable WHERE user_id = ? AND is_active = 1',
        [userId],
      );

      return result.first['count'] as int? ?? 0;
    } catch (e) {
      print('Error getting reminder count: $e');
      return 0;
    }
  }

  // ==================== END REMINDER OPERATIONS ====================

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
      await db.delete(_remindersTable);
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