import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EmbeddingService {
  static final EmbeddingService _instance = EmbeddingService._internal();
  factory EmbeddingService() => _instance;
  EmbeddingService._internal();

  // Nomic Atlas API for embeddings (free tier available)
  static const String _nomicBaseUrl = 'https://api-atlas.nomic.ai/v1/embedding/text';
  static String get _nomicApiKey => dotenv.env['NOMIC_API_KEY'] ?? '';

  // Embedding dimension (Nomic uses 768 by default)
  static const int embeddingDimension = 768;

  // Track if API is working to avoid repeated failures
  bool _useApiEmbeddings = true;
  int _apiFailureCount = 0;
  static const int _maxApiFailures = 3;

  Future<void> initialize() async {
    print('EmbeddingService initialized');
    print('Nomic API key present: ${_nomicApiKey.isNotEmpty}');
  }

  /// Generate embedding for a text string
  /// Returns a list of doubles representing the embedding vector
  Future<List<double>> generateEmbedding(String text, {bool isQuery = false}) async {
    // Check if API key is configured
    if (_nomicApiKey.isEmpty || _nomicApiKey == 'your_nomic_api_key_here') {
      print('Nomic API key not configured, using fallback embedding');
      return _generateSimpleEmbedding(text);
    }

    // If API has failed too many times, use fallback directly
    if (!_useApiEmbeddings) {
      print('Using fallback embedding (API disabled after $_apiFailureCount failures)');
      return _generateSimpleEmbedding(text);
    }

    try {
      // Determine task type based on whether it's a query or document
      String taskType = isQuery ? 'search_query' : 'search_document';

      print('Calling Nomic API for embedding (attempt ${_apiFailureCount + 1})...');

      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse(_nomicBaseUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_nomicApiKey',
          },
          body: jsonEncode({
            'texts': [text],
            'task_type': taskType,
            'model': 'nomic-embed-text-v1.5',
          }),
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final embeddings = data['embeddings'] as List;
          if (embeddings.isNotEmpty) {
            // Reset failure count on success
            _apiFailureCount = 0;
            final embedding = (embeddings[0] as List).map((e) => (e as num).toDouble()).toList();
            print('Generated embedding with ${embedding.length} dimensions');
            return embedding;
          }
        }

        print('Nomic API error: ${response.statusCode} - ${response.body}');
        _handleApiFailure();
        return _generateSimpleEmbedding(text);
      } finally {
        client.close();
      }

    } catch (e) {
      print('Error generating embedding: $e');
      _handleApiFailure();
      return _generateSimpleEmbedding(text);
    }
  }

  void _handleApiFailure() {
    _apiFailureCount++;
    if (_apiFailureCount >= _maxApiFailures) {
      print('Disabling Nomic API after $_maxApiFailures failures. Using fallback embeddings.');
      _useApiEmbeddings = false;
    }
  }

  /// Reset API usage (call this to retry API after fixing issues)
  void resetApiUsage() {
    _useApiEmbeddings = true;
    _apiFailureCount = 0;
    print('Nomic API usage reset');
  }

  /// Simple fallback embedding using TF-IDF-like approach
  /// This is an improved implementation for when API is unavailable
  List<double> _generateSimpleEmbedding(String text) {
    print('Using fallback simple embedding for: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');

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
    final stopWords = {'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been',
      'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
      'should', 'may', 'might', 'must', 'shall', 'can', 'to', 'of', 'in', 'for',
      'on', 'with', 'at', 'by', 'from', 'as', 'and', 'or', 'but', 'if', 'i', 'me',
      'my', 'we', 'our', 'you', 'your', 'it', 'its', 'this', 'that', 'what', 'which'};

    for (int i = 0; i < words.length; i++) {
      String word = words[i];
      if (word.isEmpty) continue;

      // Give less weight to stop words
      double wordWeight = stopWords.contains(word) ? 0.3 : 1.0;

      // Use hash to determine positions in embedding
      int hash = word.hashCode.abs();

      // Distribute word influence across multiple dimensions (more spread for better similarity)
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
    final normalized = _normalizeVector(embedding);
    print('Fallback embedding generated with ${normalized.length} dimensions');
    return normalized;
  }

  /// Normalize a vector to unit length (for cosine similarity)
  List<double> _normalizeVector(List<double> vector) {
    double magnitude = 0.0;
    for (double v in vector) {
      magnitude += v * v;
    }
    magnitude = sqrt(magnitude);

    if (magnitude == 0) {
      return vector;
    }

    return vector.map((v) => v / magnitude).toList();
  }

  /// Calculate cosine similarity between two embeddings
  /// Returns a value between -1 and 1 (1 = identical, 0 = orthogonal, -1 = opposite)
  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      print('Warning: Embedding dimension mismatch: ${a.length} vs ${b.length}');
      return 0.0;
    }

    double dotProduct = 0.0;
    double magnitudeA = 0.0;
    double magnitudeB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      magnitudeA += a[i] * a[i];
      magnitudeB += b[i] * b[i];
    }

    magnitudeA = sqrt(magnitudeA);
    magnitudeB = sqrt(magnitudeB);

    if (magnitudeA == 0 || magnitudeB == 0) {
      return 0.0;
    }

    return dotProduct / (magnitudeA * magnitudeB);
  }

  /// Search for similar memories using embeddings
  /// Returns memories sorted by similarity score with recency bonus
  List<ScoredMemory> searchSimilar({
    required List<double> queryEmbedding,
    required List<MemoryWithEmbedding> memories,
    int topK = 5,
    double similarityThreshold = 0.3,
  }) {
    List<ScoredMemory> scoredMemories = [];
    DateTime now = DateTime.now();

    for (var memory in memories) {
      if (memory.embedding == null || memory.embedding!.isEmpty) {
        continue;
      }

      // Calculate base similarity
      double similarity = cosineSimilarity(queryEmbedding, memory.embedding!);

      // Apply recency bonus (memories from last 30 days get up to 0.1 bonus)
      Duration age = now.difference(memory.createdAt);
      double recencyBonus = 0.0;
      if (age.inDays < 30) {
        recencyBonus = 0.1 * (1 - (age.inDays / 30));
      }

      double finalScore = similarity + recencyBonus;

      if (similarity >= similarityThreshold) {
        scoredMemories.add(ScoredMemory(
          memoryId: memory.id,
          content: memory.content,
          createdAt: memory.createdAt,
          similarity: similarity,
          recencyBonus: recencyBonus,
          finalScore: finalScore,
        ));
      }
    }

    // Sort by final score (descending)
    scoredMemories.sort((a, b) => b.finalScore.compareTo(a.finalScore));

    // Return top K results
    return scoredMemories.take(topK).toList();
  }

  void dispose() {
    // No persistent client to close since we create new ones per request
  }
}

/// Helper class to hold memory data with embedding
class MemoryWithEmbedding {
  final String id;
  final String content;
  final DateTime createdAt;
  final List<double>? embedding;

  MemoryWithEmbedding({
    required this.id,
    required this.content,
    required this.createdAt,
    this.embedding,
  });
}

/// Helper class to hold scored search results
class ScoredMemory {
  final String memoryId;
  final String content;
  final DateTime createdAt;
  final double similarity;
  final double recencyBonus;
  final double finalScore;

  ScoredMemory({
    required this.memoryId,
    required this.content,
    required this.createdAt,
    required this.similarity,
    required this.recencyBonus,
    required this.finalScore,
  });

  @override
  String toString() {
    return 'ScoredMemory(similarity: ${similarity.toStringAsFixed(3)}, recency: ${recencyBonus.toStringAsFixed(3)}, final: ${finalScore.toStringAsFixed(3)})';
  }
}
