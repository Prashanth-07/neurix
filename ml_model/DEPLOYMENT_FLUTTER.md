# Deployment Strategy: On-Device Flutter (TFLite)

## Overview

**Deployment Method**: TensorFlow Lite (TFLite)
**Platform**: Android (Flutter)
**No API Required**: Model runs entirely on-device

---

## Why TFLite (Not ONNX)?

| Factor | TFLite | ONNX Runtime |
|--------|--------|--------------|
| Flutter Support | Excellent (official plugin) | Limited |
| Android Optimization | Native, hardware accelerated | Good |
| Model Size | Smaller with quantization | Larger |
| Documentation | Extensive | Less for Flutter |
| GPU Delegate | Yes | Limited |

**Winner: TFLite** - Better Flutter integration and Android optimization

---

## Flutter Integration

### Required Packages

```yaml
# pubspec.yaml
dependencies:
  tflite_flutter: ^0.10.4
  tflite_flutter_helper: ^0.4.0
```

### Project Structure

```
lib/
├── services/
│   ├── intent_classifier_service.dart  # New service
│   └── llm_service.dart                # Existing (modified)
│
assets/
├── models/
│   ├── intent_model.tflite             # Model file
│   └── vocab.txt                       # Tokenizer vocabulary
```

### Asset Configuration

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/models/intent_model.tflite
    - assets/models/vocab.txt
```

---

## Implementation: IntentClassifierService

```dart
// lib/services/intent_classifier_service.dart

import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

class IntentClassifierService {
  static final IntentClassifierService _instance = IntentClassifierService._internal();
  factory IntentClassifierService() => _instance;
  IntentClassifierService._internal();

  Interpreter? _interpreter;
  List<String>? _vocab;
  bool _isInitialized = false;

  // Class labels
  static const List<String> labels = [
    'save',
    'search',
    'reminder',
    'cancel_all',
    'cancel_specific',
    'unclear'
  ];

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Load TFLite model
      _interpreter = await Interpreter.fromAsset('models/intent_model.tflite');

      // Load vocabulary for tokenization
      final vocabString = await rootBundle.loadString('assets/models/vocab.txt');
      _vocab = vocabString.split('\n');

      _isInitialized = true;
      print('[IntentClassifier] Initialized successfully');
    } catch (e) {
      print('[IntentClassifier] Error initializing: $e');
      rethrow;
    }
  }

  /// Classify user input and return intent
  Future<IntentResult> classify(String text) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Tokenize input
    final inputIds = _tokenize(text);

    // Prepare input tensor
    final input = [inputIds];

    // Prepare output tensor
    final output = List.filled(1, List.filled(6, 0.0));

    // Run inference
    _interpreter!.run(input, output);

    // Get prediction
    final probabilities = output[0];
    final maxIndex = _argMax(probabilities);
    final confidence = probabilities[maxIndex];

    // If confidence is low, return unclear
    if (confidence < 0.7) {
      return IntentResult(
        intent: 'unclear',
        confidence: confidence,
        allProbabilities: Map.fromIterables(labels, probabilities),
      );
    }

    return IntentResult(
      intent: labels[maxIndex],
      confidence: confidence,
      allProbabilities: Map.fromIterables(labels, probabilities),
    );
  }

  List<int> _tokenize(String text) {
    // Simple tokenization - replace with proper BERT tokenizer
    // This is a placeholder - actual implementation needs WordPiece tokenizer
    final tokens = text.toLowerCase().split(' ');
    final ids = <int>[];

    // Add [CLS] token
    ids.add(101);

    for (final token in tokens) {
      final index = _vocab?.indexOf(token) ?? 0;
      ids.add(index > 0 ? index : 100); // 100 = [UNK]
    }

    // Add [SEP] token
    ids.add(102);

    // Pad to max length (64)
    while (ids.length < 64) {
      ids.add(0);
    }

    return ids.take(64).toList();
  }

  int _argMax(List<double> list) {
    int maxIndex = 0;
    double maxValue = list[0];
    for (int i = 1; i < list.length; i++) {
      if (list[i] > maxValue) {
        maxValue = list[i];
        maxIndex = i;
      }
    }
    return maxIndex;
  }

  void dispose() {
    _interpreter?.close();
  }
}

class IntentResult {
  final String intent;
  final double confidence;
  final Map<String, double> allProbabilities;

  IntentResult({
    required this.intent,
    required this.confidence,
    required this.allProbabilities,
  });

  @override
  String toString() => 'IntentResult(intent: $intent, confidence: ${confidence.toStringAsFixed(3)})';
}
```

---

## Modified Flow in home_screen.dart

```dart
// Before (using LLM):
final llmService = LLMService();
final intent = await llmService.detectIntent(_transcribedText);

// After (using on-device model):
final classifier = IntentClassifierService();
final result = await classifier.classify(_transcribedText);
final intent = result.intent;

// Then use LLM only when needed:
switch (intent) {
  case 'save':
    // No LLM needed - save directly
    await _handleSaveMemory(_transcribedText);
    break;
  case 'search':
    // Use LLM for response generation
    await _handleSearch(_transcribedText);
    break;
  case 'reminder':
    // Use LLM for parsing
    await _handleReminder(_transcribedText);
    break;
  case 'cancel_all':
    // No LLM needed - cancel all directly
    await _handleCancelAll();
    break;
  case 'cancel_specific':
    // Use LLM to extract keyword
    await _handleCancelSpecific(_transcribedText);
    break;
  case 'unclear':
    // No LLM needed - ask for clarification
    _showClarificationDialog();
    break;
}
```

---

## Model Conversion Pipeline

### Step 1: Train in Python (PyTorch/TensorFlow)
```python
# Save as SavedModel or ONNX first
model.save('saved_model/')
```

### Step 2: Convert to TFLite
```python
import tensorflow as tf

# Load saved model
converter = tf.lite.TFLiteConverter.from_saved_model('saved_model/')

# Apply INT8 quantization
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.int8]

# Convert
tflite_model = converter.convert()

# Save
with open('intent_model.tflite', 'wb') as f:
    f.write(tflite_model)
```

### Step 3: Copy to Flutter assets
```
cp intent_model.tflite neurix/assets/models/
cp vocab.txt neurix/assets/models/
```

---

## Performance Expectations

| Metric | Expected Value |
|--------|----------------|
| Model Size | 25-30 MB |
| Load Time | ~500ms (first time) |
| Inference Time | 50-100ms |
| Memory Usage | ~50MB |
| Battery Impact | Minimal |

---

## Testing Checklist

- [ ] Model loads successfully
- [ ] Tokenization works correctly
- [ ] All 6 classes return correctly
- [ ] Confidence threshold works
- [ ] Performance is acceptable
- [ ] Memory usage is reasonable
- [ ] Works offline
- [ ] Works on low-end devices

---

## Alternative: Use tensorflow_lite_flutter Package

If `tflite_flutter` has issues, use the official TensorFlow Lite package:

```yaml
dependencies:
  tensorflow_lite_flutter: ^0.0.1
```

This has better support but slightly different API.

---

## Summary

1. **Train** MobileBERT model in Python
2. **Convert** to TFLite with INT8 quantization
3. **Add** to Flutter assets
4. **Create** IntentClassifierService
5. **Replace** LLM detectIntent() calls
6. **Test** thoroughly on device
