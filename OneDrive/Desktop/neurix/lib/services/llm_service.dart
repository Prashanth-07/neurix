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
  static const String _modelName = 'llama3-8b-8192';

  // Service status
  LLMStatus _status = LLMStatus.uninitialized;
  
  // Status stream
  final StreamController<LLMStatus> _statusController = StreamController<LLMStatus>.broadcast();
  Stream<LLMStatus> get statusStream => _statusController.stream;
  LLMStatus get currentStatus => _status;

  // HTTP client for API calls
  late http.Client _httpClient;
  
  Future<void> initialize() async {
    try {
      print('Initializing LLM Service with Groq API...');
      _updateStatus(LLMStatus.loading);
      
      // Initialize HTTP client
      _httpClient = http.Client();
      
      // Test API connectivity
      bool apiReady = await _testGroqConnection();
      
      if (apiReady) {
        _updateStatus(LLMStatus.ready);
        print('LLM Service initialized successfully with Groq API (llama3-8b-8192)');
      } else {
        _updateStatus(LLMStatus.error);
        print('Failed to connect to Groq API');
        throw Exception('Groq API connection failed');
      }
      
    } catch (e) {
      print('Error initializing LLM Service: $e');
      _updateStatus(LLMStatus.error);
      throw e;
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
      if (_status != LLMStatus.ready) {
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

      // System prompt (enhanced for better temporal reasoning)
      String systemPrompt = '''You are a helpful assistant that answers questions based on the user's personal memories.
Use ONLY the provided memories to answer the question.
If the memories don't contain information to answer the question, say you don't know.
Do not make up information or use knowledge outside of the provided memories.

CRITICAL TEMPORAL RULE: When there are conflicting memories about the same thing (like location of an item), 
ALWAYS prioritize the MOST RECENT memory. The most recent memory is the current truth.
Older conflicting memories should be acknowledged but not treated as current information.

For example: If someone asks "where are my keys?" and there are two memories:
- MOST RECENT: "I kept my keys in cupboard" 
- Older: "I kept my keys in car"
Answer should focus on the cupboard (most recent) and maybe mention they were previously in the car.

Be warm, concise, and helpful in your response.

ADDITIONAL REQUIREMENTS:
- Keep responses under 50 words
- When there are conflicting memories, clearly state which is most recent
- If you notice patterns, offer brief helpful suggestions''';

      // User message with memory context
      String userMessage = '''Question: $query

Here are the relevant memories to answer this question:

$memoryContext''';

      // Make API call to Groq
      String response = await _callGroqAPI(systemPrompt, userMessage);
      return _cleanResponse(response);
      
    } catch (e) {
      print('Error generating contextual response: $e');
      return _getFallbackResponse(query, relevantMemories);
    }
  }

  // Parse reminder requests using Groq API
  Future<ReminderRequest?> parseReminderRequest(String userInput) async {
    try {
      if (_status != LLMStatus.ready) {
        return _parseFallbackReminder(userInput);
      }

      String systemPrompt = '''You are a reminder parsing assistant. Parse reminder requests and extract structured information.
Respond ONLY with valid JSON. Do not include any other text.''';

      String userMessage = '''Parse this reminder request and extract the task and timing information:

User request: "$userInput"

Extract:
- task: what to remind (string)
- timeInMinutes: how many minutes from now (number, 0 if not specified)
- type: "timer" (countdown), "alarm" (specific time), or "scheduled" (date/time)
- scheduledTime: if specific time mentioned, format as ISO string, otherwise null

Examples:
"Remind me to call mom in 30 minutes" ΓåÆ {"task": "call mom", "timeInMinutes": 30, "type": "timer", "scheduledTime": null}
"Remind me to take medicine at 8 PM" ΓåÆ {"task": "take medicine", "timeInMinutes": 0, "type": "alarm", "scheduledTime": "2024-01-01T20:00:00.000Z"}

Respond with JSON only:''';

      String response = await _callGroqAPI(systemPrompt, userMessage);
      return _parseReminderFromResponse(response, userInput);
      
    } catch (e) {
      print('Error parsing reminder request: $e');
      return _parseFallbackReminder(userInput);
    }
  }

  // Generate smart insights about memories using Groq API
  Future<String> generateMemoryInsights(List<Memory> memories) async {
    try {
      if (_status != LLMStatus.ready || memories.isEmpty) {
        return "No insights available at the moment.";
      }

      String memoryText = memories
          .take(20) // Limit to recent memories
          .map((m) => "${_formatDate(m.createdAt)}: ${m.content}")
          .join("\n");

      String systemPrompt = '''You are a personal memory analyst. Analyze the user's memories and provide helpful insights.
Be supportive, encouraging, and brief. Focus on patterns, frequently mentioned items, and helpful suggestions.''';

      String userMessage = '''Analyze these personal memories and provide helpful insights or patterns:

$memoryText

Provide insights about:
- Common themes or patterns you notice
- Important items or locations mentioned frequently  
- Helpful reminders or suggestions based on patterns
- Positive observations about their habits

Keep response under 100 words and be encouraging:''';

      return await _callGroqAPI(systemPrompt, userMessage);
      
    } catch (e) {
      print('Error generating memory insights: $e');
      return "I notice you've been keeping track of various important things. That's great for staying organized!";
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
      return "I don't have any relevant memories stored for that question. You might want to add some memories first!";
    }
    
    return "Based on your memories, I found ${memories.length} relevant item${memories.length == 1 ? '' : 's'}:\n\n" +
        memories.map((m) => "Γ√ó ${m.content}").take(3).join('\n') +
        (memories.length > 3 ? '\n\n...and ${memories.length - 3} more.' : '');
  }

  String _cleanResponse(String response) {
    // Remove common AI response prefixes and clean up
    response = response.trim();
    
    List<String> prefixesToRemove = [
      'Response:',
      'Answer:',
      'Here\'s',
      'Based on your memories,',
    ];
    
    for (String prefix in prefixesToRemove) {
      if (response.startsWith(prefix)) {
        response = response.substring(prefix.length).trim();
      }
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
