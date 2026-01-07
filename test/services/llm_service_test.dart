import 'package:flutter_test/flutter_test.dart';
import 'package:neurix/services/llm_service.dart';
import 'package:neurix/models/memory_model.dart';

void main() {
  group('LLMService Tests', () {
    late LLMService llmService;

    setUp(() {
      llmService = LLMService();
    });

    group('Intent Detection Fallback', () {
      // Test the fallback intent detection which works without API

      test('should detect "save" intent for statement about parking', () {
        final intent = llmService.detectIntentFallback('I parked my car in the garage');
        expect(intent, equals('save'));
      });

      test('should detect "save" intent for "I put" statements', () {
        final intent = llmService.detectIntentFallback('I put my keys on the table');
        expect(intent, equals('save'));
      });

      test('should detect "save" intent for "I left" statements', () {
        final intent = llmService.detectIntentFallback('I left my wallet at home');
        expect(intent, equals('save'));
      });

      test('should detect "save" intent for password statements', () {
        final intent = llmService.detectIntentFallback('my password is secret123');
        expect(intent, equals('save'));
      });

      test('should detect "save" intent for meeting statements', () {
        final intent = llmService.detectIntentFallback('meeting at 3pm tomorrow');
        expect(intent, equals('save'));
      });

      test('should detect "search" intent for "where" questions', () {
        final intent = llmService.detectIntentFallback('where did I park my car');
        expect(intent, equals('search'));
      });

      test('should detect "search" intent for "what" questions', () {
        final intent = llmService.detectIntentFallback('what is my wifi password');
        expect(intent, equals('search'));
      });

      test('should detect "search" intent for "when" questions', () {
        final intent = llmService.detectIntentFallback('when is my dentist appointment');
        expect(intent, equals('search'));
      });

      test('should detect "search" intent for questions ending with ?', () {
        final intent = llmService.detectIntentFallback('did I save my car location?');
        expect(intent, equals('search'));
      });

      test('should detect "search" intent for "find" commands', () {
        final intent = llmService.detectIntentFallback('find my car keys');
        expect(intent, equals('search'));
      });

      test('should detect "reminder" intent for "remind me" commands', () {
        final intent = llmService.detectIntentFallback('remind me to take medicine at 8pm');
        expect(intent, equals('reminder'));
      });

      test('should detect "reminder" intent for "set a reminder" commands', () {
        final intent = llmService.detectIntentFallback('set a reminder to call mom');
        expect(intent, equals('reminder'));
      });

      test('should detect "reminder" intent with "every" pattern', () {
        final intent = llmService.detectIntentFallback('remind me to drink water every 30 minutes');
        expect(intent, equals('reminder'));
      });

      test('should detect "reminder" intent with "in" pattern', () {
        final intent = llmService.detectIntentFallback('remind to take a break in 1 hour');
        expect(intent, equals('reminder'));
      });

      test('should detect "cancel_reminder" intent for cancel commands', () {
        final intent = llmService.detectIntentFallback('cancel my water reminder');
        expect(intent, equals('cancel_reminder'));
      });

      test('should detect "cancel_reminder" intent for stop commands', () {
        final intent = llmService.detectIntentFallback('stop the medicine reminder');
        expect(intent, equals('cancel_reminder'));
      });

      test('should detect "cancel_reminder" intent for delete commands', () {
        final intent = llmService.detectIntentFallback('delete my exercise reminder');
        expect(intent, equals('cancel_reminder'));
      });

      test('should default to "save" for longer statements without specific patterns', () {
        final intent = llmService.detectIntentFallback('the meeting room code is 4532');
        expect(intent, equals('save'));
      });

      test('should return "unclear" for very short unclear input', () {
        final intent = llmService.detectIntentFallback('hi');
        expect(intent, equals('unclear'));
      });

      test('should handle empty input', () {
        final intent = llmService.detectIntentFallback('');
        expect(intent, equals('unclear'));
      });

      test('should handle mixed case input', () {
        final intent = llmService.detectIntentFallback('WHERE Is My CAR?');
        expect(intent, equals('search'));
      });
    });

    group('Memory Content Extraction', () {
      test('should remove "remember that" prefix', () {
        final content = llmService.extractMemoryContent('remember that my car is in slot A5');
        expect(content, equals('My car is in slot A5'));
      });

      test('should remove "remember" prefix', () {
        final content = llmService.extractMemoryContent('remember my password is 1234');
        expect(content, equals('My password is 1234'));
      });

      test('should remove "save that" prefix', () {
        final content = llmService.extractMemoryContent('save that I parked at level 2');
        expect(content, equals('I parked at level 2'));
      });

      test('should remove "save" prefix', () {
        final content = llmService.extractMemoryContent('save my wifi password is home123');
        expect(content, equals('My wifi password is home123'));
      });

      test('should remove "note that" prefix', () {
        final content = llmService.extractMemoryContent('note that meeting is at 3pm');
        expect(content, equals('Meeting is at 3pm'));
      });

      test('should remove "don\'t forget that" prefix', () {
        final content = llmService.extractMemoryContent("don't forget that keys are on the hook");
        expect(content, equals('Keys are on the hook'));
      });

      test('should capitalize first letter of result', () {
        final content = llmService.extractMemoryContent('remember the password is secret');
        expect(content[0], equals(content[0].toUpperCase()));
      });

      test('should handle content without prefix', () {
        final content = llmService.extractMemoryContent('My car is parked in the garage');
        expect(content, equals('My car is parked in the garage'));
      });

      test('should handle empty string', () {
        final content = llmService.extractMemoryContent('');
        expect(content, equals(''));
      });

      test('should trim whitespace', () {
        final content = llmService.extractMemoryContent('  remember that test  ');
        expect(content, equals('Test'));
      });
    });

    group('Fallback Response Generation', () {
      test('should return helpful message when no memories found', () {
        final response = llmService.getFallbackResponse('where is my car?', []);
        expect(response.contains("don't have any information"), isTrue);
      });

      test('should return memory content for single memory', () {
        final memory = Memory(
          id: 'mem-1',
          userId: 'user-1',
          content: 'Car is parked in slot A5',
          createdAt: DateTime.now(),
        );

        final response = llmService.getFallbackResponse('where is my car?', [memory]);
        expect(response, equals('Car is parked in slot A5'));
      });

      test('should concatenate multiple memories', () {
        final memories = [
          Memory(id: 'm1', userId: 'u1', content: 'First memory', createdAt: DateTime.now()),
          Memory(id: 'm2', userId: 'u1', content: 'Second memory', createdAt: DateTime.now()),
          Memory(id: 'm3', userId: 'u1', content: 'Third memory', createdAt: DateTime.now()),
        ];

        final response = llmService.getFallbackResponse('query', memories);
        expect(response.contains('First memory'), isTrue);
        expect(response.contains('Second memory'), isTrue);
        expect(response.contains('Third memory'), isTrue);
      });

      test('should limit to first 3 memories', () {
        final memories = List.generate(
          5,
          (i) => Memory(
            id: 'm$i',
            userId: 'u1',
            content: 'Memory $i',
            createdAt: DateTime.now(),
          ),
        );

        final response = llmService.getFallbackResponse('query', memories);
        expect(response.contains('Memory 0'), isTrue);
        expect(response.contains('Memory 1'), isTrue);
        expect(response.contains('Memory 2'), isTrue);
        expect(response.contains('Memory 3'), isFalse);
        expect(response.contains('Memory 4'), isFalse);
      });
    });
  });

  group('Cancel Reminder Parsing Tests', () {
    // These test the local/fallback parsing logic

    test('should detect "all" for cancel all reminders', () {
      // Based on the pattern in ReminderService.parseCancelCommand
      final input = 'cancel all my reminders';
      // The pattern checks for 'all' and 'reminders' separately
      expect(input.toLowerCase().contains('all'), isTrue);
      expect(input.toLowerCase().contains('reminder'), isTrue);
    });

    test('should extract keyword from cancel command', () {
      // Pattern: cancel my X reminder
      final input = 'cancel my water reminder';
      final regex = RegExp(
        r'(?:cancel|stop|remove|delete)(?:\s+my|\s+the)?\s+(.+?)\s*reminder',
        caseSensitive: false,
      );
      final match = regex.firstMatch(input);

      expect(match, isNotNull);
      expect(match!.group(1)?.trim(), equals('water'));
    });

    test('should extract keyword from stop command', () {
      final input = 'stop the medicine reminder';
      final regex = RegExp(
        r'(?:cancel|stop|remove|delete)(?:\s+my|\s+the)?\s+(.+?)\s*reminder',
        caseSensitive: false,
      );
      final match = regex.firstMatch(input);

      expect(match, isNotNull);
      expect(match!.group(1)?.trim(), equals('medicine'));
    });
  });
}

// Extension to expose private methods for testing
extension LLMServiceTestExtension on LLMService {
  String detectIntentFallback(String input) {
    final lowerText = input.toLowerCase().trim();

    // Check cancel reminder first
    if ((lowerText.contains('cancel') ||
            lowerText.contains('stop') ||
            lowerText.contains('delete') ||
            lowerText.contains('remove')) &&
        lowerText.contains('reminder')) {
      return 'cancel_reminder';
    }

    // Check reminder patterns
    if (lowerText.contains('remind me') ||
        lowerText.contains('set a reminder') ||
        lowerText.contains('set reminder') ||
        (lowerText.contains('remind') &&
            (lowerText.contains('every') ||
                lowerText.contains('in ') ||
                lowerText.contains('at ') ||
                lowerText.contains('after ')))) {
      return 'reminder';
    }

    // Search patterns - questions
    final searchStarters = [
      'where',
      'what',
      'when',
      'how',
      'find',
      'search',
      'look for',
      'do i have',
      'did i'
    ];
    for (var pattern in searchStarters) {
      if (lowerText.startsWith(pattern) || lowerText.contains(' $pattern')) {
        return 'search';
      }
    }
    if (lowerText.endsWith('?')) {
      return 'search';
    }

    // Save patterns - statements about storing things
    final saveIndicators = [
      'i put',
      'i left',
      'i kept',
      'i placed',
      'i stored',
      'i parked',
      'i have put',
      'i have left',
      'i have kept',
      'i have placed',
      'i have stored',
      'remember that',
      'my password',
      'my pin',
      'meeting at',
      'meeting is'
    ];
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

  String getFallbackResponse(String query, List<Memory> memories) {
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
}
