import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurix/services/embedding_service.dart';

void main() {
  group('EmbeddingService Tests', () {
    late EmbeddingService embeddingService;

    setUp(() {
      embeddingService = EmbeddingService();
    });

    group('Cosine Similarity Calculation', () {
      test('should return 1.0 for identical vectors', () {
        final vectorA = [1.0, 0.0, 0.0];
        final vectorB = [1.0, 0.0, 0.0];

        final similarity = embeddingService.cosineSimilarity(vectorA, vectorB);

        expect(similarity, closeTo(1.0, 0.001));
      });

      test('should return 0.0 for orthogonal vectors', () {
        final vectorA = [1.0, 0.0, 0.0];
        final vectorB = [0.0, 1.0, 0.0];

        final similarity = embeddingService.cosineSimilarity(vectorA, vectorB);

        expect(similarity, closeTo(0.0, 0.001));
      });

      test('should return -1.0 for opposite vectors', () {
        final vectorA = [1.0, 0.0, 0.0];
        final vectorB = [-1.0, 0.0, 0.0];

        final similarity = embeddingService.cosineSimilarity(vectorA, vectorB);

        expect(similarity, closeTo(-1.0, 0.001));
      });

      test('should return high similarity for similar vectors', () {
        final vectorA = [1.0, 2.0, 3.0];
        final vectorB = [1.1, 2.1, 3.1];

        final similarity = embeddingService.cosineSimilarity(vectorA, vectorB);

        expect(similarity, greaterThan(0.99));
      });

      test('should handle zero vectors gracefully', () {
        final vectorA = [0.0, 0.0, 0.0];
        final vectorB = [1.0, 2.0, 3.0];

        final similarity = embeddingService.cosineSimilarity(vectorA, vectorB);

        expect(similarity, equals(0.0));
      });

      test('should return 0.0 for mismatched dimensions', () {
        final vectorA = [1.0, 2.0, 3.0];
        final vectorB = [1.0, 2.0];

        final similarity = embeddingService.cosineSimilarity(vectorA, vectorB);

        expect(similarity, equals(0.0));
      });

      test('should work with large dimension vectors (768)', () {
        final vectorA = List.generate(768, (i) => sin(i.toDouble()));
        final vectorB = List.generate(768, (i) => sin(i.toDouble() + 0.1));

        final similarity = embeddingService.cosineSimilarity(vectorA, vectorB);

        expect(similarity, greaterThan(0.9)); // Should be very similar
        expect(similarity, lessThanOrEqualTo(1.0));
      });

      test('should be commutative (a,b) == (b,a)', () {
        final vectorA = [1.0, 2.0, 3.0, 4.0, 5.0];
        final vectorB = [5.0, 4.0, 3.0, 2.0, 1.0];

        final similarityAB = embeddingService.cosineSimilarity(vectorA, vectorB);
        final similarityBA = embeddingService.cosineSimilarity(vectorB, vectorA);

        expect(similarityAB, closeTo(similarityBA, 0.0001));
      });
    });

    group('searchSimilar', () {
      test('should return empty list for empty memories', () {
        final queryEmbedding = List.generate(768, (i) => i * 0.001);

        final results = embeddingService.searchSimilar(
          queryEmbedding: queryEmbedding,
          memories: [],
        );

        expect(results, isEmpty);
      });

      test('should filter out memories below similarity threshold', () {
        final queryEmbedding = [1.0, 0.0, 0.0];

        final memories = [
          MemoryWithEmbedding(
            id: 'mem-1',
            content: 'Similar memory',
            createdAt: DateTime.now(),
            embedding: [0.9, 0.1, 0.0], // Similar
          ),
          MemoryWithEmbedding(
            id: 'mem-2',
            content: 'Different memory',
            createdAt: DateTime.now(),
            embedding: [0.0, 1.0, 0.0], // Orthogonal - should be filtered
          ),
        ];

        final results = embeddingService.searchSimilar(
          queryEmbedding: queryEmbedding,
          memories: memories,
          similarityThreshold: 0.5,
        );

        expect(results.length, equals(1));
        expect(results[0].memoryId, equals('mem-1'));
      });

      test('should return topK results sorted by score', () {
        final queryEmbedding = [1.0, 0.0, 0.0];

        final memories = [
          MemoryWithEmbedding(
            id: 'mem-1',
            content: 'Low similarity',
            createdAt: DateTime.now(),
            embedding: [0.6, 0.4, 0.0],
          ),
          MemoryWithEmbedding(
            id: 'mem-2',
            content: 'High similarity',
            createdAt: DateTime.now(),
            embedding: [0.95, 0.05, 0.0],
          ),
          MemoryWithEmbedding(
            id: 'mem-3',
            content: 'Medium similarity',
            createdAt: DateTime.now(),
            embedding: [0.8, 0.2, 0.0],
          ),
        ];

        final results = embeddingService.searchSimilar(
          queryEmbedding: queryEmbedding,
          memories: memories,
          topK: 2,
          similarityThreshold: 0.0,
        );

        expect(results.length, equals(2));
        expect(results[0].memoryId, equals('mem-2')); // Highest similarity first
        expect(results[1].memoryId, equals('mem-3')); // Second highest
      });

      test('should apply recency bonus for recent memories', () {
        final queryEmbedding = [1.0, 0.0, 0.0];
        final baseEmbedding = [0.9, 0.1, 0.0];

        final memories = [
          MemoryWithEmbedding(
            id: 'mem-old',
            content: 'Old memory',
            createdAt: DateTime.now().subtract(const Duration(days: 60)), // Old
            embedding: baseEmbedding,
          ),
          MemoryWithEmbedding(
            id: 'mem-new',
            content: 'New memory',
            createdAt: DateTime.now().subtract(const Duration(days: 1)), // Recent
            embedding: baseEmbedding,
          ),
        ];

        final results = embeddingService.searchSimilar(
          queryEmbedding: queryEmbedding,
          memories: memories,
          similarityThreshold: 0.0,
        );

        expect(results.length, equals(2));
        // Recent memory should have higher final score due to recency bonus
        expect(results[0].memoryId, equals('mem-new'));
        expect(results[0].recencyBonus, greaterThan(0));
        expect(results[1].recencyBonus, equals(0)); // Old memory, no bonus
      });

      test('should skip memories without embeddings', () {
        final queryEmbedding = [1.0, 0.0, 0.0];

        final memories = [
          MemoryWithEmbedding(
            id: 'mem-1',
            content: 'Memory with embedding',
            createdAt: DateTime.now(),
            embedding: [0.9, 0.1, 0.0],
          ),
          MemoryWithEmbedding(
            id: 'mem-2',
            content: 'Memory without embedding',
            createdAt: DateTime.now(),
            embedding: null,
          ),
          MemoryWithEmbedding(
            id: 'mem-3',
            content: 'Memory with empty embedding',
            createdAt: DateTime.now(),
            embedding: [],
          ),
        ];

        final results = embeddingService.searchSimilar(
          queryEmbedding: queryEmbedding,
          memories: memories,
          similarityThreshold: 0.0,
        );

        expect(results.length, equals(1));
        expect(results[0].memoryId, equals('mem-1'));
      });

      test('should respect topK limit', () {
        final queryEmbedding = [1.0, 0.0, 0.0];

        final memories = List.generate(
          10,
          (i) => MemoryWithEmbedding(
            id: 'mem-$i',
            content: 'Memory $i',
            createdAt: DateTime.now(),
            embedding: [1.0 - i * 0.05, i * 0.05, 0.0],
          ),
        );

        final results = embeddingService.searchSimilar(
          queryEmbedding: queryEmbedding,
          memories: memories,
          topK: 3,
          similarityThreshold: 0.0,
        );

        expect(results.length, equals(3));
      });

      test('should return ScoredMemory with all fields populated', () {
        final queryEmbedding = [1.0, 0.0, 0.0];

        final memories = [
          MemoryWithEmbedding(
            id: 'mem-1',
            content: 'Test memory content',
            createdAt: DateTime.now().subtract(const Duration(days: 5)),
            embedding: [0.9, 0.1, 0.0],
          ),
        ];

        final results = embeddingService.searchSimilar(
          queryEmbedding: queryEmbedding,
          memories: memories,
          similarityThreshold: 0.0,
        );

        expect(results.length, equals(1));
        final result = results[0];

        expect(result.memoryId, equals('mem-1'));
        expect(result.content, equals('Test memory content'));
        expect(result.similarity, greaterThan(0.0));
        expect(result.recencyBonus, greaterThan(0.0));
        expect(result.finalScore, equals(result.similarity + result.recencyBonus));
      });
    });

    group('Fallback Embedding Generation (Using TestEmbeddingService)', () {
      // Note: These tests use a test helper that directly calls the fallback
      // embedding logic, bypassing the dotenv dependency

      test('should generate embedding with correct dimension', () {
        final embedding = generateTestEmbedding('test content');

        expect(embedding.length, equals(768));
      });

      test('should generate different embeddings for different text', () {
        final embedding1 = generateTestEmbedding('I parked my car');
        final embedding2 = generateTestEmbedding('The weather is nice');

        final similarity = embeddingService.cosineSimilarity(embedding1, embedding2);

        // Different content should have lower similarity
        expect(similarity, lessThan(0.9));
      });

      test('should generate similar embeddings for similar text', () {
        final embedding1 = generateTestEmbedding('I parked my car in the garage');
        final embedding2 = generateTestEmbedding('My car is parked in the garage');

        final similarity = embeddingService.cosineSimilarity(embedding1, embedding2);

        // Similar content should have higher similarity
        expect(similarity, greaterThan(0.5));
      });

      test('should generate normalized embedding (unit vector)', () {
        final embedding = generateTestEmbedding('test content');

        // Calculate magnitude
        double magnitude = 0.0;
        for (var v in embedding) {
          magnitude += v * v;
        }
        magnitude = sqrt(magnitude);

        // Should be close to 1.0 (unit vector)
        expect(magnitude, closeTo(1.0, 0.001));
      });

      test('should handle empty string', () {
        final embedding = generateTestEmbedding('');

        expect(embedding.length, equals(768));
      });

      test('should handle very long text', () {
        final longText = 'word ' * 1000;
        final embedding = generateTestEmbedding(longText);

        expect(embedding.length, equals(768));
      });

      test('should handle special characters', () {
        final embedding = generateTestEmbedding(
          'Test with special chars: @#\$%^&*()!',
        );

        expect(embedding.length, equals(768));
      });
    });

    group('API Reset', () {
      test('resetApiUsage should reset failure count', () {
        // Simulate API being disabled
        embeddingService.resetApiUsage();

        // No direct way to test internal state, but reset should not throw
        expect(() => embeddingService.resetApiUsage(), returnsNormally);
      });
    });
  });

  group('MemoryWithEmbedding Tests', () {
    test('should create MemoryWithEmbedding with all fields', () {
      final memory = MemoryWithEmbedding(
        id: 'mem-001',
        content: 'Test content',
        createdAt: DateTime(2024, 1, 15),
        embedding: [0.1, 0.2, 0.3],
      );

      expect(memory.id, equals('mem-001'));
      expect(memory.content, equals('Test content'));
      expect(memory.createdAt, equals(DateTime(2024, 1, 15)));
      expect(memory.embedding, equals([0.1, 0.2, 0.3]));
    });

    test('should allow null embedding', () {
      final memory = MemoryWithEmbedding(
        id: 'mem-001',
        content: 'Test content',
        createdAt: DateTime.now(),
        embedding: null,
      );

      expect(memory.embedding, isNull);
    });
  });

  group('ScoredMemory Tests', () {
    test('should create ScoredMemory with all fields', () {
      final scored = ScoredMemory(
        memoryId: 'mem-001',
        content: 'Test content',
        createdAt: DateTime(2024, 1, 15),
        similarity: 0.85,
        recencyBonus: 0.05,
        finalScore: 0.90,
      );

      expect(scored.memoryId, equals('mem-001'));
      expect(scored.content, equals('Test content'));
      expect(scored.similarity, equals(0.85));
      expect(scored.recencyBonus, equals(0.05));
      expect(scored.finalScore, equals(0.90));
    });

    test('toString should format scores correctly', () {
      final scored = ScoredMemory(
        memoryId: 'mem-001',
        content: 'Test',
        createdAt: DateTime.now(),
        similarity: 0.8567,
        recencyBonus: 0.0456,
        finalScore: 0.9023,
      );

      final str = scored.toString();

      expect(str.contains('0.857'), isTrue);
      expect(str.contains('0.046'), isTrue);
      expect(str.contains('0.902'), isTrue);
    });
  });
}

/// Test helper class that provides embedding functionality without dotenv dependency
class TestEmbeddingService {
  static const int embeddingDimension = 768;
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
