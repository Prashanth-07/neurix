import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/memory_model.dart';

enum LLMStatus {
  uninitialized,
  downloading,
  loading,
  ready,
  error,
}

class ReminderRequest {
  final String task;
  final int timeInMinutes;
  final String type; // 'timer', 'alarm', 'scheduled'
  final DateTime? scheduledTime;
  final String originalText;

  ReminderRequest({
    required this.task,
    required this.timeInMinutes,
    required this.type,
    this.scheduledTime,
    required this.originalText,
  });

  factory ReminderRequest.fromJson(Map<String, dynamic> json) {
    return ReminderRequest(
      task: json['task'] ?? '',
      timeInMinutes: json['timeInMinutes'] ?? 0,
      type: json['type'] ?? 'timer',
      scheduledTime: json['scheduledTime'] != null 
          ? DateTime.parse(json['scheduledTime'])
          : null,
      originalText: json['originalText'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'task': task,
      'timeInMinutes': timeInMinutes,
      'type': type,
      'scheduledTime': scheduledTime?.toIso8601String(),
      'originalText': originalText,
    };
  }
}

class LLMService {
  static final LLMService _instance = LLMService._internal();
  factory LLMService() => _instance;
  LLMService._internal();

  // Groq API Configuration
  static String get _groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';
  static const String _groqBaseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _modelName = 'llama-3.1-8b-instant'; // Updated from deprecated llama3-8b-8192

  // Service status
  LLMStatus _status = LLMStatus.uninitialized;
  
  // Status stream
  final StreamController<LLMStatus> _statusController = StreamController<LLMStatus>.broadcast();
  Stream<LLMStatus> get statusStream => _statusController.stream;
  LLMStatus get currentStatus => _status;

  // HTTP client for API calls
  late http.Client _httpClient;
  
  Future<void> initialize() async {
    // Skip if already ready
    if (_status == LLMStatus.ready) {
      print('LLM Service already initialized');
      return;
    }

    try {
      print('Initializing LLM Service with Groq API...');
      _updateStatus(LLMStatus.loading);

      // Initialize HTTP client
      _httpClient = http.Client();

      // Test API connectivity
      bool apiReady = await _testGroqConnection();

      if (apiReady) {
        _updateStatus(LLMStatus.ready);
        print('LLM Service initialized successfully with Groq API ($_modelName)');
      } else {
        _updateStatus(LLMStatus.error);
        print('Failed to connect to Groq API');
        throw Exception('Groq API connection failed');
      }

    } catch (e) {
      print('Error initializing LLM Service: $e');
      _updateStatus(LLMStatus.error);
      rethrow;
    }
  }

  // Test Groq API connection
  Future<bool> _testGroqConnection() async {
    try {
      final response = await _httpClient.post(
        Uri.parse(_groqBaseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_groqApiKey',
        },
        body: jsonEncode({
          'model': _modelName,
          'messages': [
            {'role': 'user', 'content': 'Hi'}
          ],
          'max_tokens': 10,
        }),
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('Groq API connection test successful');
        return true;
      } else {
        print('Groq API test failed with status: ${response.statusCode}');
        print('Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Groq API connection test error: $e');
      return false;
    }
  }

  void _updateStatus(LLMStatus status) {
    _status = status;
    _statusController.add(status);
  }

  // Generate contextual response based on memories using Groq API
  Future<String> generateContextualResponse(
    String query,
    List<Memory> relevantMemories,
  ) async {
    try {
      print('   [LLM] Status: $_status');
      if (_status != LLMStatus.ready) {
        print('   [LLM] Not ready, using fallback');
        return _getFallbackResponse(query, relevantMemories);
      }

      // Sort memories by date (most recent first) and prepare context
      List<Memory> sortedMemories = List.from(relevantMemories)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      String memoryContext = sortedMemories.isEmpty
          ? "No relevant memories found."
          : sortedMemories
              .asMap()
              .entries
              .map((entry) {
                int index = entry.key;
                Memory memory = entry.value;
                String timeLabel = index == 0 ? "MOST RECENT" : "Older";
                return "$timeLabel (${_formatDate(memory.createdAt)}): ${memory.content}";
              })
              .join("\n");

      // System prompt for Llama 3 8B - direct and simple
      String systemPrompt = '''Answer the question using ONLY the memories provided. Give direct answers in under 20 words.

Rules:
1. If memories conflict, use the MOST RECENT one
2. Never say "according to memory" - just answer directly
3. Say "I don't know" only if no relevant memory exists

Example: Memory says "keys in bag" → Answer "Your keys are in your bag."''';

      // User message with memory context
      String userMessage = '''Question: $query

Here are the relevant memories to answer this question:

$memoryContext''';

      print('   [LLM] Sending to Groq API...');
      print('   [LLM] Memory context:\n$memoryContext');

      // Make API call to Groq
      String response = await _callGroqAPI(systemPrompt, userMessage);
      String cleanedResponse = _cleanResponse(response);
      print('   [LLM] Raw response: "$response"');
      print('   [LLM] Cleaned response: "$cleanedResponse"');
      return cleanedResponse;

    } catch (e) {
      print('   [LLM] Error: $e');
      return _getFallbackResponse(query, relevantMemories);
    }
  }

  // Parse reminder requests using Groq API
  Future<ReminderRequest?> parseReminderRequest(String userInput) async {
    try {
      if (_status != LLMStatus.ready) {
        return _parseFallbackReminder(userInput);
      }

      String systemPrompt = '''Extract reminder info as JSON only. No other text.''';

      String userMessage = '''Parse: "$userInput"

Return JSON: {"task": "what to do", "timeInMinutes": number, "type": "timer|alarm", "scheduledTime": null}

Examples:
"call mom in 30 min" → {"task":"call mom","timeInMinutes":30,"type":"timer","scheduledTime":null}
"medicine at 8pm" → {"task":"medicine","timeInMinutes":0,"type":"alarm","scheduledTime":"2024-01-01T20:00:00Z"}''';

      String response = await _callGroqAPI(systemPrompt, userMessage);
      return _parseReminderFromResponse(response, userInput);
      
    } catch (e) {
      print('Error parsing reminder request: $e');
      return _parseFallbackReminder(userInput);
    }
  }


  // Core Groq API call method
  Future<String> _callGroqAPI(String systemPrompt, String userMessage) async {
    try {
      final response = await _httpClient.post(
        Uri.parse(_groqBaseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_groqApiKey',
        },
        body: jsonEncode({
          'model': _modelName,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userMessage}
          ],
          'max_tokens': 150,
          'temperature': 0.3,
          'top_p': 0.9,
        }),
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        Map<String, dynamic> responseData = jsonDecode(response.body);
        String content = responseData['choices'][0]['message']['content'];
        print('Groq API response received: ${content.length} characters');
        return content.trim();
      } else {
        print('Groq API error: ${response.statusCode} - ${response.body}');
        throw Exception('Groq API call failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Error calling Groq API: $e');
      rethrow;
    }
  }

  // Helper methods

  ReminderRequest? _parseReminderFromResponse(String response, String originalInput) {
    try {
      // Clean the response to extract JSON
      String jsonStr = response.trim();
      
      // Find JSON content between braces
      int startIndex = jsonStr.indexOf('{');
      int endIndex = jsonStr.lastIndexOf('}');
      
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        jsonStr = jsonStr.substring(startIndex, endIndex + 1);
      }
      
      Map<String, dynamic> parsed = jsonDecode(jsonStr);
      parsed['originalText'] = originalInput;
      
      return ReminderRequest.fromJson(parsed);
    } catch (e) {
      print('Error parsing reminder JSON: $e');
      return _parseFallbackReminder(originalInput);
    }
  }

  ReminderRequest? _parseFallbackReminder(String input) {
    // Simple pattern-based fallback parsing
    String lowerInput = input.toLowerCase();
    
    // Extract task
    String task = input;
    if (lowerInput.contains('remind me to ')) {
      task = input.split('remind me to ')[1].split(' in ')[0].split(' at ')[0];
    }
    
    // Extract time
    int minutes = 0;
    String type = 'timer';
    
    if (lowerInput.contains(' minutes')) {
      RegExp exp = RegExp(r'(\d+)\s*minutes?');
      Match? match = exp.firstMatch(lowerInput);
      if (match != null) {
        minutes = int.parse(match.group(1)!);
      }
    } else if (lowerInput.contains(' hour')) {
      RegExp exp = RegExp(r'(\d+)\s*hours?');
      Match? match = exp.firstMatch(lowerInput);
      if (match != null) {
        minutes = int.parse(match.group(1)!) * 60;
      }
    }
    
    return ReminderRequest(
      task: task.trim(),
      timeInMinutes: minutes,
      type: type,
      originalText: input,
    );
  }

  String _getFallbackResponse(String query, List<Memory> memories) {
    if (memories.isEmpty) {
      return "I don't have any information about that. Try adding a memory first!";
    }

    // For single memory, try to give a direct answer
    if (memories.length == 1) {
      return memories.first.content;
    }

    // For multiple memories, list the most recent ones concisely
    return memories.take(3).map((m) => m.content).join('. ');
  }

  String _cleanResponse(String response) {
    response = response.trim();

    // Remove common prefixes
    final prefixes = ['Answer:', 'Response:', 'Based on', 'According to'];
    for (var p in prefixes) {
      if (response.toLowerCase().startsWith(p.toLowerCase())) {
        response = response.substring(p.length).trim();
      }
    }

    // Capitalize first letter
    if (response.isNotEmpty) {
      response = response[0].toUpperCase() + response.substring(1);
    }
    return response;
  }

  String _formatDate(DateTime date) {
    DateTime now = DateTime.now();
    Duration diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'today';
    } else if (diff.inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  // Check if LLM is ready
  bool get isReady => _status == LLMStatus.ready;

  // Dispose resources
  void dispose() {
    _httpClient.close();
    _statusController.close();
  }
}