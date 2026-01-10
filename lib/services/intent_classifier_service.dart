import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// Intent classification result
class IntentResult {
  final String intent;
  final double confidence;
  final Map<String, double> allScores;

  IntentResult({
    required this.intent,
    required this.confidence,
    required this.allScores,
  });

  @override
  String toString() => 'IntentResult(intent: $intent, confidence: ${confidence.toStringAsFixed(3)})';
}

/// On-device intent classifier using ONNX Runtime with MobileBERT model
///
/// Classifies user input into 6 intents:
/// - save: User wants to store information
/// - search: User wants to find/retrieve information
/// - reminder: User wants to set a reminder
/// - cancel_all: User wants to cancel all reminders
/// - cancel_specific: User wants to cancel a specific reminder
/// - unclear: Input is ambiguous or doesn't fit categories
class IntentClassifierService {
  static final IntentClassifierService _instance = IntentClassifierService._internal();
  factory IntentClassifierService() => _instance;
  IntentClassifierService._internal();

  // Model configuration
  static const String _modelAssetPath = 'assets/models/intent_model.onnx';
  static const String _vocabAssetPath = 'assets/models/vocab.txt';
  static const int _maxLength = 64;
  static const double _confidenceThreshold = 0.7;

  // Label mapping (must match training)
  static const Map<int, String> _id2label = {
    0: 'save',
    1: 'search',
    2: 'reminder',
    3: 'cancel_all',
    4: 'cancel_specific',
    5: 'unclear',
  };

  // ONNX Runtime session and vocab
  OrtSession? _session;
  Map<String, int>? _vocab;
  bool _isInitialized = false;

  // Special tokens
  static const int _clsTokenId = 101;  // [CLS]
  static const int _sepTokenId = 102;  // [SEP]
  static const int _padTokenId = 0;    // [PAD]
  static const int _unkTokenId = 100;  // [UNK]

  /// Initialize the classifier
  Future<void> initialize() async {
    if (_isInitialized) {
      print('[IntentClassifier] Already initialized');
      return;
    }

    try {
      print('[IntentClassifier] Initializing...');

      // Initialize ONNX Runtime
      OrtEnv.instance.init();

      // Load vocabulary
      await _loadVocabulary();

      // Load ONNX model
      await _loadModel();

      _isInitialized = true;
      print('[IntentClassifier] Initialized successfully');

    } catch (e) {
      print('[IntentClassifier] Initialization error: $e');
      rethrow;
    }
  }

  /// Load vocabulary from assets
  Future<void> _loadVocabulary() async {
    print('[IntentClassifier] Loading vocabulary...');

    final vocabString = await rootBundle.loadString(_vocabAssetPath);
    final lines = vocabString.split('\n');

    _vocab = {};
    for (int i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isNotEmpty) {
        _vocab![token] = i;
      }
    }

    print('[IntentClassifier] Loaded ${_vocab!.length} vocabulary tokens');
  }

  /// Load ONNX model
  Future<void> _loadModel() async {
    print('[IntentClassifier] Loading ONNX model...');

    // Load model from assets
    final modelData = await rootBundle.load(_modelAssetPath);
    final bytes = modelData.buffer.asUint8List();

    // Create ONNX session options
    final sessionOptions = OrtSessionOptions();

    // Create ONNX session from buffer
    _session = OrtSession.fromBuffer(bytes, sessionOptions);

    print('[IntentClassifier] Model loaded successfully');
  }

  /// Tokenize text using WordPiece tokenization
  List<int> _tokenize(String text) {
    if (_vocab == null) {
      throw StateError('Vocabulary not loaded');
    }

    // Lowercase and clean text
    text = text.toLowerCase().trim();

    // Simple whitespace + punctuation tokenization
    final List<String> words = [];
    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      final char = text[i];

      if (char == ' ' || char == '\t' || char == '\n') {
        if (buffer.isNotEmpty) {
          words.add(buffer.toString());
          buffer.clear();
        }
      } else if (_isPunctuation(char)) {
        if (buffer.isNotEmpty) {
          words.add(buffer.toString());
          buffer.clear();
        }
        words.add(char);
      } else {
        buffer.write(char);
      }
    }

    if (buffer.isNotEmpty) {
      words.add(buffer.toString());
    }

    // WordPiece tokenization
    final List<int> tokenIds = [];

    for (final word in words) {
      final wordTokens = _wordPieceTokenize(word);
      tokenIds.addAll(wordTokens);
    }

    return tokenIds;
  }

  /// Check if character is punctuation
  bool _isPunctuation(String char) {
    final code = char.codeUnitAt(0);
    // ASCII punctuation ranges
    return (code >= 33 && code <= 47) ||   // !"#$%&'()*+,-./
           (code >= 58 && code <= 64) ||   // :;<=>?@
           (code >= 91 && code <= 96) ||   // [\]^_`
           (code >= 123 && code <= 126);   // {|}~
  }

  /// WordPiece tokenization for a single word
  List<int> _wordPieceTokenize(String word) {
    final List<int> tokens = [];

    // Check if whole word is in vocab
    if (_vocab!.containsKey(word)) {
      tokens.add(_vocab![word]!);
      return tokens;
    }

    // Try to break into subwords
    int start = 0;
    bool isFirst = true;

    while (start < word.length) {
      int end = word.length;
      String? curSubstr;
      int? curId;

      while (start < end) {
        String substr = word.substring(start, end);
        if (!isFirst) {
          substr = '##$substr';
        }

        if (_vocab!.containsKey(substr)) {
          curSubstr = substr;
          curId = _vocab![substr];
          break;
        }

        end--;
      }

      if (curSubstr == null) {
        // Character not in vocab, use [UNK]
        tokens.add(_unkTokenId);
        start++;
        isFirst = false;
      } else {
        tokens.add(curId!);
        start = end;
        isFirst = false;
      }
    }

    return tokens;
  }

  /// Prepare input tensors for the model
  Map<String, List<int>> _prepareInputs(String text) {
    // Tokenize
    final tokenIds = _tokenize(text);

    // Add special tokens: [CLS] ... [SEP]
    final List<int> inputIds = [_clsTokenId];
    inputIds.addAll(tokenIds.take(_maxLength - 2)); // Leave room for [CLS] and [SEP]
    inputIds.add(_sepTokenId);

    // Pad to max length
    while (inputIds.length < _maxLength) {
      inputIds.add(_padTokenId);
    }

    // Create attention mask (1 for real tokens, 0 for padding)
    final List<int> attentionMask = inputIds.map((id) => id != _padTokenId ? 1 : 0).toList();

    return {
      'input_ids': inputIds,
      'attention_mask': attentionMask,
    };
  }

  /// Classify user input intent
  /// Returns IntentResult with intent label and confidence
  Future<IntentResult> classifyIntent(String text) async {
    if (!_isInitialized) {
      print('[IntentClassifier] Not initialized, initializing now...');
      await initialize();
    }

    if (_session == null) {
      throw StateError('Model not loaded');
    }

    print('[IntentClassifier] Classifying: "$text"');

    // Prepare inputs
    final inputs = _prepareInputs(text);
    final inputIds = inputs['input_ids']!;
    final attentionMask = inputs['attention_mask']!;

    // Create input tensors - shape [1, 64] with int64 values
    final inputIdsData = Int64List.fromList(inputIds);
    final attentionMaskData = Int64List.fromList(attentionMask);

    final inputIdsTensor = OrtValueTensor.createTensorWithDataList(
      inputIdsData,
      [1, _maxLength],
    );

    final attentionMaskTensor = OrtValueTensor.createTensorWithDataList(
      attentionMaskData,
      [1, _maxLength],
    );

    // Run inference
    final runOptions = OrtRunOptions();
    final outputs = await _session!.runAsync(
      runOptions,
      {
        'input_ids': inputIdsTensor,
        'attention_mask': attentionMaskTensor,
      },
    );

    // Get output probabilities
    final outputList = outputs!;
    final outputTensor = outputList[0]!;
    final outputData = outputTensor.value as List;

    // Flatten and convert to double
    List<double> probs;
    if (outputData[0] is List) {
      probs = (outputData[0] as List).map((e) => (e as num).toDouble()).toList();
    } else {
      probs = outputData.map((e) => (e as num).toDouble()).toList();
    }

    // Release tensors
    inputIdsTensor.release();
    attentionMaskTensor.release();
    runOptions.release();
    for (var output in outputList) {
      output?.release();
    }

    // Find best prediction
    int bestIdx = 0;
    double bestProb = probs[0];
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > bestProb) {
        bestProb = probs[i];
        bestIdx = i;
      }
    }

    // Build all scores map
    final allScores = <String, double>{};
    for (int i = 0; i < probs.length; i++) {
      allScores[_id2label[i]!] = probs[i];
    }

    // Get intent label
    String intent = _id2label[bestIdx]!;

    // Apply confidence threshold - fallback to 'unclear' if confidence is low
    if (bestProb < _confidenceThreshold) {
      print('[IntentClassifier] Low confidence ($bestProb), falling back to unclear');
      intent = 'unclear';
    }

    final result = IntentResult(
      intent: intent,
      confidence: bestProb,
      allScores: allScores,
    );

    print('[IntentClassifier] Result: $result');
    return result;
  }

  /// Detect intent and return just the intent string (for compatibility with LLMService)
  Future<String> detectIntent(String userInput) async {
    final result = await classifyIntent(userInput);

    // Map cancel_all and cancel_specific to cancel_reminder for backward compatibility
    if (result.intent == 'cancel_all' || result.intent == 'cancel_specific') {
      return 'cancel_reminder';
    }

    return result.intent;
  }

  /// Get detailed classification with cancel type
  /// Returns: 'all' for cancel_all, specific topic for cancel_specific, null for other intents
  Future<String?> getCancelType(String userInput) async {
    final result = await classifyIntent(userInput);

    if (result.intent == 'cancel_all') {
      return 'all';
    } else if (result.intent == 'cancel_specific') {
      // Extract the specific topic from the input
      return _extractCancelTopic(userInput);
    }

    return null;
  }

  /// Extract the topic/keyword from a cancel_specific request
  String _extractCancelTopic(String userInput) {
    final lowerInput = userInput.toLowerCase();

    // Common patterns to remove
    final patternsToRemove = [
      'cancel the reminder',
      'cancel my reminder',
      'cancel reminder',
      'delete the reminder',
      'delete my reminder',
      'delete reminder',
      'stop the reminder',
      'stop my reminder',
      'stop reminder',
      'remove the reminder',
      'remove my reminder',
      'remove reminder',
      'turn off the reminder',
      'turn off my reminder',
      'turn off reminder',
      'i don\'t want the',
      'i don\'t need the',
      'stop reminding me to',
      'stop reminding me about',
      'cancel the',
      'delete the',
      'stop the',
      'remove the',
      'to',
      'about',
      'for',
      'reminder',
      'anymore',
    ];

    String topic = lowerInput;

    // Remove common patterns
    for (final pattern in patternsToRemove) {
      topic = topic.replaceAll(pattern, ' ');
    }

    // Clean up
    topic = topic.replaceAll(RegExp(r'\s+'), ' ').trim();

    // If nothing left, try to extract key noun
    if (topic.isEmpty || topic.length < 2) {
      // Extract words after "cancel/delete/stop/remove ... reminder"
      final match = RegExp(r'(?:cancel|delete|stop|remove)\s+(?:the\s+)?(?:my\s+)?(\w+)\s+reminder')
          .firstMatch(lowerInput);
      if (match != null) {
        topic = match.group(1) ?? '';
      }
    }

    return topic.isNotEmpty ? topic : userInput;
  }

  /// Check if classifier is ready
  bool get isReady => _isInitialized;

  /// Dispose resources
  void dispose() {
    _session?.release();
    _session = null;
    _vocab = null;
    _isInitialized = false;
    print('[IntentClassifier] Disposed');
  }
}
