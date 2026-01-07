import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurix/models/memory_model.dart';

void main() {
  group('Memory Model Tests', () {
    group('Memory Creation', () {
      test('should create a Memory with required fields', () {
        final memory = Memory(
          id: 'test-id-123',
          userId: 'user-456',
          content: 'I parked my car in the garage',
          createdAt: DateTime(2024, 1, 15, 10, 30),
        );

        expect(memory.id, equals('test-id-123'));
        expect(memory.userId, equals('user-456'));
        expect(memory.content, equals('I parked my car in the garage'));
        expect(memory.createdAt, equals(DateTime(2024, 1, 15, 10, 30)));
        expect(memory.embedding, isNull);
        expect(memory.metadata, isNull);
      });

      test('should create a Memory with optional embedding', () {
        final embedding = List.generate(768, (i) => i * 0.001);
        final memory = Memory(
          id: 'test-id-123',
          userId: 'user-456',
          content: 'Test content',
          createdAt: DateTime.now(),
          embedding: embedding,
        );

        expect(memory.embedding, isNotNull);
        expect(memory.embedding!.length, equals(768));
        expect(memory.embedding![0], equals(0.0));
        expect(memory.embedding![1], equals(0.001));
      });

      test('should create a Memory with optional metadata', () {
        final memory = Memory(
          id: 'test-id-123',
          userId: 'user-456',
          content: 'Test content',
          createdAt: DateTime.now(),
          metadata: {'source': 'voice', 'confidence': 0.95},
        );

        expect(memory.metadata, isNotNull);
        expect(memory.metadata!['source'], equals('voice'));
        expect(memory.metadata!['confidence'], equals(0.95));
      });
    });

    group('Memory.fromMap (SQLite deserialization)', () {
      test('should deserialize basic memory from map', () {
        final map = {
          'id': 'mem-001',
          'user_id': 'user-123',
          'content': 'My password is secret123',
          'created_at': '2024-01-15T10:30:00.000',
        };

        final memory = Memory.fromMap(map);

        expect(memory.id, equals('mem-001'));
        expect(memory.userId, equals('user-123'));
        expect(memory.content, equals('My password is secret123'));
        expect(memory.createdAt, equals(DateTime(2024, 1, 15, 10, 30)));
      });

      test('should deserialize embedding from JSON string', () {
        final embedding = [0.1, 0.2, 0.3, 0.4, 0.5];
        final map = {
          'id': 'mem-001',
          'user_id': 'user-123',
          'content': 'Test',
          'created_at': '2024-01-15T10:30:00.000',
          'embedding': jsonEncode(embedding),
        };

        final memory = Memory.fromMap(map);

        expect(memory.embedding, isNotNull);
        expect(memory.embedding!.length, equals(5));
        expect(memory.embedding![0], equals(0.1));
        expect(memory.embedding![4], equals(0.5));
      });

      test('should deserialize embedding from List directly', () {
        final embedding = [0.1, 0.2, 0.3];
        final map = {
          'id': 'mem-001',
          'user_id': 'user-123',
          'content': 'Test',
          'created_at': '2024-01-15T10:30:00.000',
          'embedding': embedding,
        };

        final memory = Memory.fromMap(map);

        expect(memory.embedding, isNotNull);
        expect(memory.embedding!.length, equals(3));
      });

      test('should handle null embedding gracefully', () {
        final map = {
          'id': 'mem-001',
          'user_id': 'user-123',
          'content': 'Test',
          'created_at': '2024-01-15T10:30:00.000',
          'embedding': null,
        };

        final memory = Memory.fromMap(map);
        expect(memory.embedding, isNull);
      });

      test('should deserialize metadata from JSON string', () {
        final metadata = {'category': 'personal', 'tags': ['car', 'parking']};
        final map = {
          'id': 'mem-001',
          'user_id': 'user-123',
          'content': 'Test',
          'created_at': '2024-01-15T10:30:00.000',
          'metadata': jsonEncode(metadata),
        };

        final memory = Memory.fromMap(map);

        expect(memory.metadata, isNotNull);
        expect(memory.metadata!['category'], equals('personal'));
      });

      test('should handle missing fields with defaults', () {
        final map = <String, dynamic>{};

        final memory = Memory.fromMap(map);

        expect(memory.id, equals(''));
        expect(memory.userId, equals(''));
        expect(memory.content, equals(''));
        expect(memory.createdAt, isNotNull);
      });

      test('should handle malformed embedding JSON gracefully', () {
        final map = {
          'id': 'mem-001',
          'user_id': 'user-123',
          'content': 'Test',
          'created_at': '2024-01-15T10:30:00.000',
          'embedding': 'not-valid-json',
        };

        final memory = Memory.fromMap(map);
        expect(memory.embedding, isNull);
      });
    });

    group('Memory.toMap (SQLite serialization)', () {
      test('should serialize basic memory to map', () {
        final memory = Memory(
          id: 'mem-001',
          userId: 'user-123',
          content: 'I parked at level 3',
          createdAt: DateTime(2024, 1, 15, 10, 30),
        );

        final map = memory.toMap();

        expect(map['id'], equals('mem-001'));
        expect(map['user_id'], equals('user-123'));
        expect(map['content'], equals('I parked at level 3'));
        expect(map['created_at'], equals('2024-01-15T10:30:00.000'));
        expect(map['embedding'], isNull);
        expect(map['metadata'], isNull);
      });

      test('should serialize embedding as JSON string', () {
        final embedding = [0.1, 0.2, 0.3];
        final memory = Memory(
          id: 'mem-001',
          userId: 'user-123',
          content: 'Test',
          createdAt: DateTime.now(),
          embedding: embedding,
        );

        final map = memory.toMap();

        expect(map['embedding'], isA<String>());
        final decodedEmbedding = jsonDecode(map['embedding']);
        expect(decodedEmbedding, equals([0.1, 0.2, 0.3]));
      });

      test('should serialize metadata as JSON string', () {
        final memory = Memory(
          id: 'mem-001',
          userId: 'user-123',
          content: 'Test',
          createdAt: DateTime.now(),
          metadata: {'key': 'value'},
        );

        final map = memory.toMap();

        expect(map['metadata'], isA<String>());
        final decodedMetadata = jsonDecode(map['metadata']);
        expect(decodedMetadata['key'], equals('value'));
      });
    });

    group('Memory.copyWith', () {
      test('should create a copy with updated content', () {
        final original = Memory(
          id: 'mem-001',
          userId: 'user-123',
          content: 'Original content',
          createdAt: DateTime(2024, 1, 15),
        );

        final copy = original.copyWith(content: 'Updated content');

        expect(copy.content, equals('Updated content'));
        expect(copy.id, equals(original.id));
        expect(copy.userId, equals(original.userId));
        expect(copy.createdAt, equals(original.createdAt));
      });

      test('should create a copy with updated embedding', () {
        final original = Memory(
          id: 'mem-001',
          userId: 'user-123',
          content: 'Test',
          createdAt: DateTime.now(),
          embedding: [0.1, 0.2],
        );

        final newEmbedding = [0.3, 0.4, 0.5];
        final copy = original.copyWith(embedding: newEmbedding);

        expect(copy.embedding, equals(newEmbedding));
        expect(original.embedding, equals([0.1, 0.2])); // Original unchanged
      });

      test('should keep original values when not specified', () {
        final original = Memory(
          id: 'mem-001',
          userId: 'user-123',
          content: 'Test',
          createdAt: DateTime(2024, 1, 15),
          embedding: [0.1],
          metadata: {'key': 'value'},
        );

        final copy = original.copyWith();

        expect(copy.id, equals(original.id));
        expect(copy.userId, equals(original.userId));
        expect(copy.content, equals(original.content));
        expect(copy.createdAt, equals(original.createdAt));
        expect(copy.embedding, equals(original.embedding));
        expect(copy.metadata, equals(original.metadata));
      });
    });

    group('Memory.toString', () {
      test('should truncate long content in toString', () {
        final longContent = 'A' * 100;
        final memory = Memory(
          id: 'mem-001',
          userId: 'user-123',
          content: longContent,
          createdAt: DateTime.now(),
        );

        final str = memory.toString();

        expect(str.contains('...'), isTrue);
        expect(str.length, lessThan(longContent.length + 50));
      });

      test('should not truncate short content', () {
        final memory = Memory(
          id: 'mem-001',
          userId: 'user-123',
          content: 'Short content',
          createdAt: DateTime.now(),
        );

        final str = memory.toString();

        expect(str.contains('Short content'), isTrue);
        expect(str.contains('...'), isFalse);
      });
    });

    group('Serialization round-trip', () {
      test('should survive toMap/fromMap round trip', () {
        final original = Memory(
          id: 'mem-001',
          userId: 'user-123',
          content: 'I left my keys on the kitchen table',
          createdAt: DateTime(2024, 1, 15, 10, 30, 45),
          embedding: List.generate(768, (i) => i * 0.001),
          metadata: {'source': 'voice', 'confidence': 0.95},
        );

        final map = original.toMap();
        final restored = Memory.fromMap(map);

        expect(restored.id, equals(original.id));
        expect(restored.userId, equals(original.userId));
        expect(restored.content, equals(original.content));
        expect(restored.createdAt.year, equals(original.createdAt.year));
        expect(restored.createdAt.month, equals(original.createdAt.month));
        expect(restored.createdAt.day, equals(original.createdAt.day));
        expect(restored.embedding!.length, equals(original.embedding!.length));
        expect(restored.metadata!['source'], equals(original.metadata!['source']));
      });
    });
  });

  group('MemorySearchResult Tests', () {
    test('should create MemorySearchResult with all fields', () {
      final memory = Memory(
        id: 'mem-001',
        userId: 'user-123',
        content: 'Test memory',
        createdAt: DateTime.now(),
      );

      final result = MemorySearchResult(
        memory: memory,
        similarity: 0.85,
        relevanceScore: 0.90,
      );

      expect(result.memory, equals(memory));
      expect(result.similarity, equals(0.85));
      expect(result.relevanceScore, equals(0.90));
    });

    test('toString should format similarity scores', () {
      final memory = Memory(
        id: 'mem-001',
        userId: 'user-123',
        content: 'Test',
        createdAt: DateTime.now(),
      );

      final result = MemorySearchResult(
        memory: memory,
        similarity: 0.8567,
        relevanceScore: 0.9123,
      );

      final str = result.toString();

      expect(str.contains('0.857'), isTrue);
      expect(str.contains('0.912'), isTrue);
    });
  });

  group('QueryResponse Tests', () {
    test('should create QueryResponse with all fields', () {
      final memory = Memory(
        id: 'mem-001',
        userId: 'user-123',
        content: 'Test memory',
        createdAt: DateTime.now(),
      );

      final searchResult = MemorySearchResult(
        memory: memory,
        similarity: 0.85,
        relevanceScore: 0.90,
      );

      final response = QueryResponse(
        answer: 'Your car is parked in the garage.',
        relevantMemories: [searchResult],
        query: 'Where is my car?',
        confidence: 0.95,
      );

      expect(response.answer, equals('Your car is parked in the garage.'));
      expect(response.relevantMemories.length, equals(1));
      expect(response.query, equals('Where is my car?'));
      expect(response.confidence, equals(0.95));
    });

    test('should allow null confidence', () {
      final response = QueryResponse(
        answer: 'Test answer',
        relevantMemories: [],
        query: 'Test query',
      );

      expect(response.confidence, isNull);
    });

    test('toString should truncate long answers', () {
      final longAnswer = 'A' * 200;
      final response = QueryResponse(
        answer: longAnswer,
        relevantMemories: [],
        query: 'Test query',
      );

      final str = response.toString();

      expect(str.contains('...'), isTrue);
    });
  });
}
