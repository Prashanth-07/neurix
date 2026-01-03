import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/memory_model.dart';

enum LLMStatus {
  uninitialized,
  loading,
  ready,
  error,
}

/// LLM Service for Neurix App
///
/// Handles 3 types of LLM calls:
/// 1. detectIntent() - Classify user input into: save, search, reminder, cancel_reminder, unclear
/// 2. generateContextualResponse() - Generate response for memory search results
/// 3. parseReminderFromVoice() - Parse reminder details (recurring/one-time, time, message)
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

  /// ===========================================
  /// LLM CALL 2: SEARCH RESPONSE GENERATION
  /// ===========================================
  /// Generates a natural response based on retrieved memories
  Future<String> generateContextualResponse(
    String query,
    List<Memory> relevantMemories,
  ) async {
    print('[LLM-2] generateContextualResponse() - Query: "$query"');

    try {
      if (_status != LLMStatus.ready) {
        print('[LLM-2] Not ready, using fallback');
        return _getFallbackResponse(query, relevantMemories);
      }

      // Sort memories by date (most recent first)
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

      String systemPrompt = '''Answer using ONLY the memories provided. Be direct, under 20 words.
- Use MOST RECENT memory if there are conflicts
- Never say "according to memory" - just answer
- Say "I don't know" only if no relevant memory exists''';

      String userMessage = '''Question: $query

Memories:
$memoryContext''';

      print('[LLM-2] Calling Groq API with ${sortedMemories.length} memories...');

      String response = await _callGroqAPI(systemPrompt, userMessage);
      String cleanedResponse = _cleanResponse(response);
      print('[LLM-2] Response: "$cleanedResponse"');
      return cleanedResponse;

    } catch (e) {
      print('[LLM-2] Error: $e');
      return _getFallbackResponse(query, relevantMemories);
    }
  }

  /// ===========================================
  /// LLM CALL 1: INTENT DETECTION
  /// ===========================================
  /// Detects user intent from voice input
  /// Returns: 'save', 'search', 'reminder', 'cancel_reminder', or 'unclear'
  Future<String> detectIntent(String userInput) async {
    print('[LLM-1] detectIntent() - Input: "$userInput"');

    try {
      if (_status != LLMStatus.ready) {
        print('[LLM-1] Not ready, initializing...');
        await initialize();
      }

      String systemPrompt = '''Classify user input into ONE intent. Reply with ONLY one word.

Intents:
- save: User states information to remember (locations, facts, passwords, events)
- search: User asks a question or wants to find saved information
- reminder: User wants to set a new reminder (contains "remind me", "set reminder", time phrases)
- cancel_reminder: User wants to stop/cancel/delete a reminder
- unclear: Input is too vague or doesn't fit any category

Reply with exactly one word: save, search, reminder, cancel_reminder, or unclear''';

      String userMessage = userInput;

      print('[LLM-1] Calling Groq API...');
      String response = await _callGroqAPI(systemPrompt, userMessage);
      String intent = response.toLowerCase().trim();

      // Extract intent word from response
      if (intent.contains('cancel_reminder') || intent.contains('cancel reminder')) {
        intent = 'cancel_reminder';
      } else if (intent.contains('save')) {
        intent = 'save';
      } else if (intent.contains('search')) {
        intent = 'search';
      } else if (intent.contains('reminder')) {
        intent = 'reminder';
      } else if (intent.contains('unclear')) {
        intent = 'unclear';
      } else {
        print('[LLM-1] Unexpected response: "$response", using fallback');
        return _detectIntentFallback(userInput);
      }

      print('[LLM-1] Detected intent: "$intent"');
      return intent;

    } catch (e) {
      print('[LLM-1] Error: $e, using fallback');
      return _detectIntentFallback(userInput);
    }
  }

  /// Fallback intent detection using simple patterns (used when LLM fails)
  String _detectIntentFallback(String userInput) {
    final lowerText = userInput.toLowerCase().trim();
    print('[LLM] _detectIntentFallback() - Input: "$lowerText"');

    // Check cancel reminder first
    if ((lowerText.contains('cancel') || lowerText.contains('stop') ||
         lowerText.contains('delete') || lowerText.contains('remove')) &&
        lowerText.contains('reminder')) {
      return 'cancel_reminder';
    }

    // Check reminder patterns
    if (lowerText.contains('remind me') || lowerText.contains('set a reminder') ||
        lowerText.contains('set reminder') ||
        (lowerText.contains('remind') && (lowerText.contains('every') ||
         lowerText.contains('in ') || lowerText.contains('at ') || lowerText.contains('after ')))) {
      return 'reminder';
    }

    // Search patterns - questions
    final searchStarters = ['where', 'what', 'when', 'how', 'find', 'search', 'look for', 'do i have', 'did i'];
    for (var pattern in searchStarters) {
      if (lowerText.startsWith(pattern) || lowerText.contains(' $pattern')) {
        return 'search';
      }
    }
    if (lowerText.endsWith('?')) {
      return 'search';
    }

    // Save patterns - statements about storing things
    final saveIndicators = ['i put', 'i left', 'i kept', 'i placed', 'i stored', 'i parked',
                           'i have put', 'i have left', 'i have kept', 'i have placed', 'i have stored',
                           'remember that', 'my password', 'my pin', 'meeting at', 'meeting is'];
    for (var pattern in saveIndicators) {
      if (lowerText.contains(pattern)) {
        return 'save';
      }
    }

    // If it's a longer statement (3+ words), assume it's something to save
    if (lowerText.split(' ').length >= 3) {
      return 'save';
    }

    return 'unclear';
  }

  /// Extract the memory content from user input
  /// Removes command words like "remember", "save", etc.
  String extractMemoryContent(String userInput) {
    var content = userInput.trim();

    // Remove common prefixes
    final prefixesToRemove = [
      'remember that',
      'remember',
      'save that',
      'save',
      'store that',
      'store',
      'note that',
      'note',
      'keep in mind that',
      'keep in mind',
      'don\'t forget that',
      'don\'t forget',
    ];

    final lowerContent = content.toLowerCase();
    for (var prefix in prefixesToRemove) {
      if (lowerContent.startsWith(prefix)) {
        content = content.substring(prefix.length).trim();
        break;
      }
    }

    // Capitalize first letter
    if (content.isNotEmpty) {
      content = content[0].toUpperCase() + content.substring(1);
    }

    return content;
  }

  /// ===========================================
  /// LLM CALL 3: REMINDER PARSING
  /// ===========================================

  /// ===========================================
  /// LLM CALL 4: CANCEL REMINDER PARSING
  /// ===========================================
  /// Parses which reminder to cancel from user input
  /// Returns: 'all' for all reminders, or the reminder keyword to search
  Future<String?> parseCancelReminderRequest(String userInput) async {
    print('[LLM-4] parseCancelReminderRequest() - Input: "$userInput"');

    try {
      if (_status != LLMStatus.ready) {
        print('[LLM-4] Not ready, initializing...');
        await initialize();
      }

      String systemPrompt = '''Extract which reminder to cancel from user input.

Rules:
- If user wants to cancel ALL reminders, return exactly: all
- If user wants to cancel a SPECIFIC reminder, return just the keyword (e.g., "water", "medicine", "call mom")
- Extract the main subject/task word from the request

Examples:
"delete all reminders" → all
"cancel all my reminders" → all
"stop all reminders" → all
"remove every reminder" → all
"cancel my water reminder" → water
"delete the medicine reminder" → medicine
"stop reminding me to drink water" → water
"remove the call mom reminder" → call mom
"I don't want the exercise reminder anymore" → exercise

Return ONLY the keyword or "all", nothing else.''';

      String userMessage = userInput;

      print('[LLM-4] Calling Groq API...');
      String response = await _callGroqAPI(systemPrompt, userMessage);
      String result = response.toLowerCase().trim();

      // Clean up response
      result = result.replaceAll('"', '').replaceAll("'", '').trim();

      print('[LLM-4] Result: "$result"');

      if (result.isEmpty) {
        return null;
      }

      return result;

    } catch (e) {
      print('[LLM-4] Error: $e');
      return null;
    }
  }
  /// Parses reminder details from voice input
  /// Returns: type (oneTime/recurring), message, intervalMinutes, scheduledTime
  Future<Map<String, dynamic>?> parseReminderFromVoice(String userInput) async {
    print('[LLM-3] parseReminderFromVoice() - Input: "$userInput"');

    try {
      if (_status != LLMStatus.ready) {
        print('[LLM-3] Not ready, initializing...');
        await initialize();
      }

      String systemPrompt = '''Parse reminder and return JSON only.

JSON format:
{"type":"oneTime|recurring","message":"Task","timeType":"duration|static|null","timeValue":"string|null","intervalMinutes":number|null}

Rules:
- "every X min/hour" → type=recurring, intervalMinutes=X (convert hours to minutes)
- "in/after X min/hour" → type=oneTime, timeType=duration, timeValue="X minutes" or "X hours"
- "at X PM/AM" or "at X o'clock" → type=oneTime, timeType=static, timeValue="X PM" or "X AM"
- message = just the task (capitalized), no time words

Examples:
"remind me to drink water every 30 minutes" → {"type":"recurring","message":"Drink water","timeType":null,"timeValue":null,"intervalMinutes":30}
"remind me to drink water every 2 hours" → {"type":"recurring","message":"Drink water","timeType":null,"timeValue":null,"intervalMinutes":120}
"remind me to call mom in 5 minutes" → {"type":"oneTime","message":"Call mom","timeType":"duration","timeValue":"5 minutes","intervalMinutes":null}
"remind me to call mom after 2 hours" → {"type":"oneTime","message":"Call mom","timeType":"duration","timeValue":"2 hours","intervalMinutes":null}
"remind me to take medicine at 4pm" → {"type":"oneTime","message":"Take medicine","timeType":"static","timeValue":"4 PM","intervalMinutes":null}
"remind me to wake up at 7 in the morning" → {"type":"oneTime","message":"Wake up","timeType":"static","timeValue":"7 AM","intervalMinutes":null}

Return ONLY JSON, no extra text.''';

      String userMessage = userInput;

      print('[LLM-3] Calling Groq API...');
      String response = await _callGroqAPI(systemPrompt, userMessage);
      print('[LLM-3] Response: "$response"');

      // Parse JSON from response
      String jsonStr = response.trim();
      int startIndex = jsonStr.indexOf('{');
      int endIndex = jsonStr.lastIndexOf('}');

      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        jsonStr = jsonStr.substring(startIndex, endIndex + 1);
      }

      Map<String, dynamic> parsed = jsonDecode(jsonStr);
      print('[LLM-3] Parsed JSON: $parsed');

      // Validate required fields
      if (parsed['message'] == null || parsed['type'] == null) {
        print('[LLM-3] Missing required fields');
        return null;
      }

      // Calculate scheduledTime based on timeType and timeValue
      if (parsed['type'] == 'oneTime') {
        DateTime? scheduledTime = _calculateScheduledTime(
          parsed['timeType'] as String?,
          parsed['timeValue'] as String?,
        );
        parsed['scheduledTime'] = scheduledTime;
        print('[LLM-3] Calculated scheduledTime: $scheduledTime');
      }

      // Ensure proper defaults
      if (parsed['type'] == 'oneTime' && parsed['scheduledTime'] == null) {
        parsed['scheduledTime'] = DateTime.now().add(const Duration(minutes: 5));
        print('[LLM-3] Using default 5 minutes from now');
      } else if (parsed['type'] == 'recurring') {
        if (parsed['intervalMinutes'] == null || parsed['intervalMinutes'] == 0) {
          parsed['intervalMinutes'] = 30;
          print('[LLM-3] Using default interval of 30 minutes');
        }
      }

      return parsed;

    } catch (e) {
      print('[LLM-3] Error: $e');
      return null;
    }
  }

  /// Calculate the actual scheduled DateTime from timeType and timeValue
  DateTime? _calculateScheduledTime(String? timeType, String? timeValue) {
    if (timeType == null || timeValue == null) {
      print('[LLM-3] timeType or timeValue is null');
      return null;
    }

    final now = DateTime.now();
    print('[LLM-3] Calculating time - type: $timeType, value: $timeValue, now: $now');

    if (timeType == 'duration') {
      // Parse duration like "5 minutes", "2 hours", "30 min"
      return _parseDuration(timeValue, now);
    } else if (timeType == 'static') {
      // Parse static time like "4 PM", "7 AM", "4:30 PM"
      return _parseStaticTime(timeValue, now);
    }

    return null;
  }

  /// Parse duration string and add to current time
  /// Handles: "5 minutes", "2 hours", "30 min", "1 hour"
  DateTime? _parseDuration(String timeValue, DateTime now) {
    final lowerValue = timeValue.toLowerCase().trim();
    print('[LLM-3] Parsing duration: "$lowerValue"');

    // Extract number from string
    final numberMatch = RegExp(r'(\d+)').firstMatch(lowerValue);
    if (numberMatch == null) {
      print('[LLM-3] No number found in duration');
      return null;
    }
    final number = int.parse(numberMatch.group(1)!);

    // Determine unit (minutes or hours)
    if (lowerValue.contains('hour')) {
      print('[LLM-3] Duration: $number hours');
      return now.add(Duration(hours: number));
    } else if (lowerValue.contains('min')) {
      print('[LLM-3] Duration: $number minutes');
      return now.add(Duration(minutes: number));
    } else if (lowerValue.contains('second')) {
      print('[LLM-3] Duration: $number seconds');
      return now.add(Duration(seconds: number));
    }

    // Default to minutes if no unit specified
    print('[LLM-3] Duration: $number minutes (default)');
    return now.add(Duration(minutes: number));
  }

  /// Parse static time string and return DateTime for today or tomorrow
  /// Handles: "4 PM", "7 AM", "4:30 PM", "16:00"
  DateTime? _parseStaticTime(String timeValue, DateTime now) {
    final lowerValue = timeValue.toLowerCase().trim();
    print('[LLM-3] Parsing static time: "$lowerValue"');

    int hour = 0;
    int minute = 0;
    bool isPM = lowerValue.contains('pm') || lowerValue.contains('p.m');
    bool isAM = lowerValue.contains('am') || lowerValue.contains('a.m');

    // Remove AM/PM markers for parsing
    String cleanTime = lowerValue
        .replaceAll('pm', '')
        .replaceAll('am', '')
        .replaceAll('p.m.', '')
        .replaceAll('a.m.', '')
        .replaceAll('p.m', '')
        .replaceAll('a.m', '')
        .trim();

    // Try to parse time formats
    if (cleanTime.contains(':')) {
      // Format: "4:30" or "16:00"
      final parts = cleanTime.split(':');
      hour = int.tryParse(parts[0].trim()) ?? 0;
      minute = int.tryParse(parts[1].trim()) ?? 0;
    } else {
      // Format: "4" or "16"
      hour = int.tryParse(cleanTime) ?? 0;
    }

    // Convert to 24-hour format
    if (isPM && hour < 12) {
      hour += 12;
    } else if (isAM && hour == 12) {
      hour = 0;
    }

    print('[LLM-3] Parsed hour: $hour, minute: $minute');

    // Create DateTime for today at the specified time
    DateTime scheduled = DateTime(now.year, now.month, now.day, hour, minute);

    // If the time has already passed today, schedule for tomorrow
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
      print('[LLM-3] Time already passed, scheduling for tomorrow');
    }

    print('[LLM-3] Scheduled time: $scheduled');
    return scheduled;
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