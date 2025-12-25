import 'dart:convert';

class Memory {
  final String id;
  final String userId;
  final String content;
  final DateTime createdAt;
  final List<double>? embedding;
  final Map<String, dynamic>? metadata;

  Memory({
    required this.id,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.embedding,
    this.metadata,
  });

  factory Memory.fromMap(Map<String, dynamic> map) {
    List<double>? embeddingList;
    if (map['embedding'] != null) {
      try {
        if (map['embedding'] is String) {
          // Stored as JSON string in SQLite
          final List<dynamic> embeddingData = jsonDecode(map['embedding']);
          embeddingList = embeddingData.cast<double>();
        } else if (map['embedding'] is List) {
          embeddingList = (map['embedding'] as List).cast<double>();
        }
      } catch (e) {
        print('Error parsing embedding: $e');
      }
    }

    Map<String, dynamic>? metadataMap;
    if (map['metadata'] != null) {
      try {
        if (map['metadata'] is String) {
          metadataMap = jsonDecode(map['metadata']);
        } else if (map['metadata'] is Map) {
          metadataMap = Map<String, dynamic>.from(map['metadata']);
        }
      } catch (e) {
        print('Error parsing metadata: $e');
        metadataMap = {};
      }
    }

    return Memory(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      content: map['content'] ?? '',
      createdAt: DateTime.parse(map['created_at'] ?? DateTime.now().toIso8601String()),
      embedding: embeddingList,
      metadata: metadataMap,
    );
  }

  factory Memory.fromFirestore(Map<String, dynamic> doc) {
    List<double>? embeddingList;
    if (doc['embedding'] != null && doc['embedding'] is List) {
      embeddingList = (doc['embedding'] as List).cast<double>();
    }

    return Memory(
      id: doc['id'] ?? '',
      userId: doc['userId'] ?? '',
      content: doc['content'] ?? '',
      createdAt: doc['createdAt'] != null 
          ? (doc['createdAt'] as dynamic).toDate() 
          : DateTime.now(),
      embedding: embeddingList,
      metadata: doc['metadata'] != null 
          ? Map<String, dynamic>.from(doc['metadata']) 
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'embedding': embedding != null ? jsonEncode(embedding) : null,
      'metadata': metadata != null ? jsonEncode(metadata) : null,
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'userId': userId,
      'content': content,
      'createdAt': createdAt,
      'embedding': embedding,
      'metadata': metadata,
    };
  }

  Memory copyWith({
    String? id,
    String? userId,
    String? content,
    DateTime? createdAt,
    List<double>? embedding,
    Map<String, dynamic>? metadata,
  }) {
    return Memory(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      embedding: embedding ?? this.embedding,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'Memory(id: $id, userId: $userId, content: ${content.length > 50 ? '${content.substring(0, 50)}...' : content})';
  }
}

class MemorySearchResult {
  final Memory memory;
  final double similarity;
  final double relevanceScore;

  MemorySearchResult({
    required this.memory,
    required this.similarity,
    required this.relevanceScore,
  });

  @override
  String toString() {
    return 'MemorySearchResult(similarity: ${similarity.toStringAsFixed(3)}, relevance: ${relevanceScore.toStringAsFixed(3)})';
  }
}

class QueryResponse {
  final String answer;
  final List<MemorySearchResult> relevantMemories;
  final String query;
  final double? confidence;

  QueryResponse({
    required this.answer,
    required this.relevantMemories,
    required this.query,
    this.confidence,
  });

  @override
  String toString() {
    return 'QueryResponse(query: $query, answer: ${answer.length > 100 ? '${answer.substring(0, 100)}...' : answer}, memories: ${relevantMemories.length})';
  }
}
