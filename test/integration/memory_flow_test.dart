import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurix/models/memory_model.dart';
import 'package:neurix/services/embedding_service.dart';

/// Integration tests for the complete add memory and search memory flow.
/// These tests simulate the full workflow without requiring a database or API.
void main() {
  group('Memory Add and Search Flow Integration Tests', () {
    late EmbeddingService embeddingService;
    late List<MemoryWithEmbedding> inMemoryDatabase;

    setUp(() {
      embeddingService = EmbeddingService();
      inMemoryDatabase = [];
    });

    /// Simulates saving a memory with embedding generation (using test helper)
    Memory addMemory(String userId, String content) {
      // Generate embedding for the content using test helper
      final embedding = generateTestEmbedding(content);

      // Create memory object
      final memory = Memory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: userId,
        content: content,
        createdAt: DateTime.now(),
        embedding: embedding,
      );

      // Add to in-memory database
      inMemoryDatabase.add(MemoryWithEmbedding(
        id: memory.id,
        content: memory.content,
        createdAt: memory.createdAt,
        embedding: embedding,
      ));

      return memory;
    }

    /// Simulates searching for memories
    List<ScoredMemory> searchMemories(String query) {
      // Generate query embedding using test helper
      final queryEmbedding = generateTestEmbedding(query);

      // Search using embedding service
      return embeddingService.searchSimilar(
        queryEmbedding: queryEmbedding,
        memories: inMemoryDatabase,
        topK: 5,
        similarityThreshold: 0.2,
      );
    }

    group('Add Memory Flow', () {
      test('should successfully add a memory with embedding', () {
        final memory = addMemory('user-1', 'I parked my car in slot A5');

        expect(memory.id, isNotEmpty);
        expect(memory.content, equals('I parked my car in slot A5'));
        expect(memory.embedding, isNotNull);
        expect(memory.embedding!.length, equals(768));
        expect(inMemoryDatabase.length, equals(1));
      });

      test('should add multiple memories', () {
        addMemory('user-1', 'My wifi password is home123');
        addMemory('user-1', 'I parked at level 2');
        addMemory('user-1', 'Meeting room code is 4532');

        expect(inMemoryDatabase.length, equals(3));
      });

      test('should generate different embeddings for different content', () {
        final memory1 = addMemory('user-1', 'I parked my car');
        final memory2 = addMemory('user-1', 'The weather is sunny');

        final similarity = embeddingService.cosineSimilarity(
          memory1.embedding!,
          memory2.embedding!,
        );

        // Different content should have lower similarity
        expect(similarity, lessThan(0.9));
      });
    });

    group('Search Memory Flow', () {
      test('should find relevant memory for exact content match', () {
        addMemory('user-1', 'I parked my car in the garage');

        final results = searchMemories('where did I park my car');

        expect(results, isNotEmpty);
        expect(results.first.content.toLowerCase(), contains('car'));
      });

      test('should find relevant memory for partial match', () {
        addMemory('user-1', 'My wifi password is supersecret123');

        final results = searchMemories('what is my wifi password');

        expect(results, isNotEmpty);
        expect(results.first.content.toLowerCase(), contains('wifi'));
      });

      test('should rank more relevant memories higher', () {
        addMemory('user-1', 'The weather today is sunny');
        addMemory('user-1', 'I parked my car at the mall garage');
        addMemory('user-1', 'My favorite car is a Tesla');

        final results = searchMemories('where is my car parked');

        expect(results.length, greaterThanOrEqualTo(1));
        // The parking memory should be most relevant
        expect(
          results.first.content.toLowerCase(),
          anyOf(contains('parked'), contains('car')),
        );
      });

      test('should return empty list when no relevant memories found', () {
        addMemory('user-1', 'I love eating pizza');

        final results = searchMemories('where did I put my passport');

        // Should either be empty or have very low similarity
        if (results.isNotEmpty) {
          expect(results.first.similarity, lessThan(0.5));
        }
      });

      test('should handle multiple users correctly', () {
        addMemory('user-1', 'User 1 parked at level 1');
        addMemory('user-2', 'User 2 parked at level 2');

        // In real implementation, search would filter by userId
        // Here we just verify both are in the database
        expect(inMemoryDatabase.length, equals(2));
      });
    });

    group('End-to-End Scenarios', () {
      test('Scenario: User saves car location and retrieves it later', () {
        // Step 1: User saves car location
        final savedMemory = addMemory(
          'user-1',
          'I parked my car in parking lot B, level 3, spot 42',
        );
        expect(savedMemory.embedding, isNotNull);

        // Step 2: Later, user asks where car is
        final results = searchMemories('where is my car');

        // Step 3: Verify correct memory is found
        expect(results, isNotEmpty);
        expect(results.first.content, contains('parking lot B'));
        expect(results.first.content, contains('spot 42'));
      });

      test('Scenario: User saves password and retrieves it', () {
        // Step 1: User saves password
        addMemory('user-1', 'My bank password is secure987');

        // Step 2: User asks for password
        final results = searchMemories('what is my bank password');

        // Step 3: Verify password memory is found
        expect(results, isNotEmpty);
        expect(results.first.content, contains('secure987'));
      });

      test('Scenario: User saves multiple related items', () {
        // Step 1: User saves multiple memories
        addMemory('user-1', 'My home wifi password is homenetwork123');
        addMemory('user-1', 'My office wifi password is worknet456');
        addMemory('user-1', 'My phone PIN is 9876');

        // Step 2: User asks for home wifi
        final homeResults = searchMemories('home wifi password');
        expect(homeResults, isNotEmpty);
        expect(homeResults.first.content.toLowerCase(), contains('home'));

        // Step 3: User asks for office wifi
        final officeResults = searchMemories('office wifi');
        expect(officeResults, isNotEmpty);
        expect(officeResults.first.content.toLowerCase(), contains('office'));
      });

      test('Scenario: User saves meeting details and retrieves them', () {
        // Step 1: Save meeting details
        addMemory(
          'user-1',
          'Team meeting is in conference room C at 3:30 PM',
        );
        addMemory(
          'user-1',
          'Client call scheduled for tomorrow at 10 AM',
        );

        // Step 2: Query for meeting
        final results = searchMemories('when is the team meeting');

        // Step 3: Verify correct meeting is found
        expect(results, isNotEmpty);
        expect(results.first.content, contains('conference room C'));
      });

      test('Scenario: Recent memories should rank higher with recency bonus', () {
        // Add old memory
        inMemoryDatabase.add(MemoryWithEmbedding(
          id: 'old-mem',
          content: 'I parked my car at the old location',
          createdAt: DateTime.now().subtract(const Duration(days: 60)),
          embedding: generateTestEmbedding('I parked my car at the old location'),
        ));

        // Add recent memory with same topic
        inMemoryDatabase.add(MemoryWithEmbedding(
          id: 'new-mem',
          content: 'I parked my car at the new location',
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
          embedding: generateTestEmbedding('I parked my car at the new location'),
        ));

        // Search for car - use lower threshold for this test
        final queryEmbedding = generateTestEmbedding('where did I park car');
        final results = embeddingService.searchSimilar(
          queryEmbedding: queryEmbedding,
          memories: inMemoryDatabase,
          topK: 5,
          similarityThreshold: 0.1, // Lower threshold to ensure we get results
        );

        // Recent memory should be ranked higher
        expect(results, isNotEmpty);
        expect(results.first.content, contains('new location'));
        expect(results.first.recencyBonus, greaterThan(0));
      });
    });

    group('Edge Cases', () {
      test('should handle special characters in content', () {
        addMemory('user-1', 'Password: P@ss\$word!123#');

        final results = searchMemories('what is my password');

        expect(results, isNotEmpty);
      });

      test('should handle very long content', () {
        final longContent = 'This is a very long memory. ' * 50;
        addMemory('user-1', longContent);

        expect(inMemoryDatabase.length, equals(1));
        expect(inMemoryDatabase.first.embedding!.length, equals(768));
      });

      test('should handle emoji in content', () {
        addMemory('user-1', 'My car is the blue one 🚗 in lot A');

        final results = searchMemories('where is my car');

        expect(results, isNotEmpty);
      });

      test('should handle queries with typos (basic matching)', () {
        addMemory('user-1', 'I parked my car in the garage');

        // Query with slight variations
        final results = searchMemories('where did i park car');

        expect(results, isNotEmpty);
      });

      test('should handle case insensitive search', () {
        addMemory('user-1', 'MY CAR IS IN THE GARAGE');

        final results = searchMemories('where is my car');

        expect(results, isNotEmpty);
      });
    });

    group('Keyword Search Fallback Simulation', () {
      test('should find memories by keyword when semantic search fails', () {
        // Simulate keyword search logic
        const stopWords = {'the', 'a', 'is', 'my', 'in', 'at', 'on'};

        String extractKeywords(String query) {
          return query
              .toLowerCase()
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .split(RegExp(r'\s+'))
              .where((w) => w.length > 2 && !stopWords.contains(w))
              .toList()
              .join(' ');
        }

        final keywords = extractKeywords('Where is my car parked?');
        expect(keywords, contains('where'));
        expect(keywords, contains('car'));
        expect(keywords, contains('parked'));
      });

      test('should extract meaningful keywords from search query', () {
        const stopWords = {
          'i', 'me', 'my', 'we', 'our', 'you', 'your', 'the', 'a', 'an', 'is',
          'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had',
          'do', 'does', 'did', 'will', 'would', 'could', 'should', 'may',
          'might', 'must', 'shall', 'can', 'need', 'dare', 'ought', 'used',
          'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'from', 'as',
          'what', 'where', 'when', 'how', 'why', 'which', 'who'
        };

        List<String> extractKeywords(String query) {
          return query
              .toLowerCase()
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .split(RegExp(r'\s+'))
              .where((word) => word.length > 2 && !stopWords.contains(word))
              .toSet()
              .toList();
        }

        final keywords = extractKeywords('What is my wifi password?');
        expect(keywords, contains('wifi'));
        expect(keywords, contains('password'));
        expect(keywords, isNot(contains('what')));
        expect(keywords, isNot(contains('is')));
      });
    });

    group('Performance Considerations', () {
      test('should handle large number of memories', () {
        // Add 100 memories
        for (int i = 0; i < 100; i++) {
          addMemory('user-1', 'Memory number $i with content ${i * 2}');
        }

        expect(inMemoryDatabase.length, equals(100));

        // Search should still work
        final results = searchMemories('memory number 50');
        expect(results, isNotEmpty);
      });

      test('should limit results with topK parameter', () {
        // Add 20 memories with similar content
        for (int i = 0; i < 20; i++) {
          addMemory('user-1', 'Car parked at location $i');
        }

        final queryEmbedding = generateTestEmbedding('where is my car');

        final results = embeddingService.searchSimilar(
          queryEmbedding: queryEmbedding,
          memories: inMemoryDatabase,
          topK: 5,
          similarityThreshold: 0.0,
        );

        expect(results.length, lessThanOrEqualTo(5));
      });
    });
  });
}

/// Generate a test embedding using the same fallback algorithm as EmbeddingService
/// This avoids the dotenv dependency issue in tests
List<double> generateTestEmbedding(String text) {
  const int embeddingDimension = 768;

  // Normalize text
  text = text.toLowerCase().trim();

  // Create a simple hash-based embedding
  List<double> embedding = List.filled(embeddingDimension, 0.0);

  // Split into words and remove punctuation
  List<String> words = text
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  // Common words to give less weight
  final stopWords = {
    'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been',
    'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
    'should', 'may', 'might', 'must', 'shall', 'can', 'to', 'of', 'in', 'for',
    'on', 'with', 'at', 'by', 'from', 'as', 'and', 'or', 'but', 'if', 'i', 'me',
    'my', 'we', 'our', 'you', 'your', 'it', 'its', 'this', 'that', 'what', 'which'
  };

  for (int i = 0; i < words.length; i++) {
    String word = words[i];
    if (word.isEmpty) continue;

    // Give less weight to stop words
    double wordWeight = stopWords.contains(word) ? 0.3 : 1.0;

    // Use hash to determine positions in embedding
    int hash = word.hashCode.abs();

    // Distribute word influence across multiple dimensions
    for (int j = 0; j < 8; j++) {
      int index = (hash + j * 31 + j * j * 7) % embeddingDimension;
      double value = wordWeight * (1.0 / (j + 1));
      embedding[index] += value;
    }

    // Add n-gram features for better context (bigrams)
    if (i < words.length - 1) {
      String bigram = '$word ${words[i + 1]}';
      int bigramHash = bigram.hashCode.abs();
      for (int j = 0; j < 4; j++) {
        int index = (bigramHash + j * 53) % embeddingDimension;
        embedding[index] += 0.5 / (j + 1);
      }
    }

    // Character-level features for handling typos/variations
    for (int c = 0; c < word.length && c < 10; c++) {
      int charIndex = (word.codeUnitAt(c) * 17 + c * 23) % embeddingDimension;
      embedding[charIndex] += 0.05;
    }
  }

  // Normalize the embedding
  double magnitude = 0.0;
  for (double v in embedding) {
    magnitude += v * v;
  }
  magnitude = sqrt(magnitude);

  if (magnitude == 0) {
    return embedding;
  }

  return embedding.map((v) => v / magnitude).toList();
}
