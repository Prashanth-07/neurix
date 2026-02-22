import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On-device wake word detection using OpenWakeWord ONNX models.
///
/// Pipeline: Raw Audio (16kHz PCM) → Mel Spectrogram → Speech Embedding → Wake Word Classifier
///
/// Uses 3 ONNX models:
///   1. melspectrogram.onnx   — converts raw audio to mel spectrogram features
///   2. embedding_model.onnx  — extracts 96-dim speech embeddings from mel frames
///   3. hey_jarvis_v0.1.onnx  — classifies embeddings as wake word or not
class WakeWordService extends ChangeNotifier {
  static final WakeWordService _instance = WakeWordService._internal();
  factory WakeWordService() => _instance;
  WakeWordService._internal();

  // ─── ONNX Sessions ───
  OrtSession? _melSession;
  OrtSession? _embeddingSession;
  OrtSession? _wakeWordSession;

  // ─── Audio Recording ───
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSubscription;

  // ─── Processing Buffers ───
  final List<double> _audioBuffer = [];
  final List<List<double>> _melBuffer = [];
  final List<List<double>> _embeddingBuffer = [];

  // ─── Frame Queue (async processing) ───
  final List<List<double>> _frameQueue = [];
  bool _isProcessing = false;

  // ─── State ───
  bool _isEnabled = false;
  bool _isListening = false;
  bool _isInitialized = false;
  String? _errorMessage;
  int _predictionCount = 0;
  DateTime? _lastDetection;

  // ─── Configuration ───
  static const int _sampleRate = 16000;
  static const int _frameSamples = 1280; // 80ms at 16kHz
  static const int _melFramesNeeded = 76; // ~760ms for one embedding
  static const int _melSlide = 8; // slide 8 frames (80ms) per embedding
  static const int _embeddingsNeeded = 16; // ~1.3s context for classifier
  static const double _threshold = 0.5;
  static const int _warmupPredictions = 2;
  static const int _detectionCooldownMs = 1000; // min ms between detections

  // ─── Enrollment ───
  static const String _enrollmentPrefKey = 'hey_neurix_enrollment';
  static const double _similarityThreshold = 0.65;
  static const int enrollmentSamples = 5;
  List<List<double>>? _enrolledEmbeddings;

  // ─── ONNX Model Input/Output Names (inspected from models) ───
  static const String _melInputName = 'input';
  static const String _embInputName = 'input_1';
  static const String _wwInputName = 'input';

  // ─── Model Asset Paths ───
  static const String _melModelPath = 'assets/models/melspectrogram.onnx';
  static const String _embModelPath = 'assets/models/embedding_model.onnx';
  static const String _wwModelPath = 'assets/models/hey_neurix.onnx';

  // ─── Callback ───
  VoidCallback? onWakeWordDetected;

  // ─── Getters ───
  bool get isEnabled => _isEnabled;
  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;
  bool get isEnrolled =>
      _enrolledEmbeddings != null &&
      _enrolledEmbeddings!.length == enrollmentSamples;
  String? get errorMessage => _errorMessage;

  static const String _prefKey = 'hey_neurix_enabled';

  // ═══════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ═══════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    if (_isInitialized) {
      print('[WakeWord] Already initialized');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_prefKey) ?? true;
    print('[WakeWord] Enabled preference: $_isEnabled');

    await _loadEnrolledEmbeddings();
    print('[WakeWord] Enrolled: $isEnrolled (${_enrolledEmbeddings?.length ?? 0} profiles)');

    try {
      await _loadModels();
      _isInitialized = true;
      _errorMessage = null;
      print('[WakeWord] All 3 ONNX models loaded successfully');
    } catch (e) {
      _errorMessage = 'Failed to load wake word models';
      print('[WakeWord] Model loading failed: $e');
    }

    if (_isEnabled && _isInitialized) {
      await _startListening();
    }
    notifyListeners();
  }

  Future<void> _loadModels() async {
    final sessionOptions = OrtSessionOptions();

    // Model 1: Mel Spectrogram
    print('[WakeWord] Loading melspectrogram.onnx...');
    final melData = await rootBundle.load(_melModelPath);
    _melSession = OrtSession.fromBuffer(
      melData.buffer.asUint8List(),
      sessionOptions,
    );
    print('[WakeWord] melspectrogram.onnx loaded (${melData.lengthInBytes} bytes)');

    // Model 2: Speech Embedding
    print('[WakeWord] Loading embedding_model.onnx...');
    final embData = await rootBundle.load(_embModelPath);
    _embeddingSession = OrtSession.fromBuffer(
      embData.buffer.asUint8List(),
      sessionOptions,
    );
    print('[WakeWord] embedding_model.onnx loaded (${embData.lengthInBytes} bytes)');

    // Model 3: Wake Word Classifier
    print('[WakeWord] Loading wake word classifier...');
    final wwData = await rootBundle.load(_wwModelPath);
    _wakeWordSession = OrtSession.fromBuffer(
      wwData.buffer.asUint8List(),
      sessionOptions,
    );
    print('[WakeWord] Wake word classifier loaded (${wwData.lengthInBytes} bytes)');
  }

  // ═══════════════════════════════════════════════════════════════════
  // PUBLIC CONTROLS
  // ═══════════════════════════════════════════════════════════════════

  Future<void> setEnabled(bool enabled) async {
    if (enabled == _isEnabled) return;
    _isEnabled = enabled;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, enabled);

    if (enabled && _isInitialized) {
      await _startListening();
    } else if (!enabled) {
      await _stopListening();
    }
    notifyListeners();
  }

  Future<void> start() async {
    if (_isListening || !_isInitialized) return;
    _isEnabled = true;
    await _startListening();
    notifyListeners();
  }

  Future<void> stop() async {
    _isEnabled = false;
    await _stopListening();
    notifyListeners();
  }

  Future<void> pause() async {
    if (!_isEnabled || !_isListening) return;
    await _stopListening();
    print('[WakeWord] Paused');
  }

  Future<void> resume() async {
    if (!_isEnabled || _isListening) return;
    if (!_isInitialized) return;
    await _startListening();
    print('[WakeWord] Resumed');
  }

  // ═══════════════════════════════════════════════════════════════════
  // ENROLLMENT
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _loadEnrolledEmbeddings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_enrollmentPrefKey);
    if (jsonStr == null) {
      _enrolledEmbeddings = null;
      return;
    }
    try {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      _enrolledEmbeddings = decoded
          .map((e) =>
              (e as List<dynamic>).map((v) => (v as num).toDouble()).toList())
          .toList();
      print(
          '[WakeWord] Loaded ${_enrolledEmbeddings!.length} enrolled embeddings');
    } catch (e) {
      print('[WakeWord] Failed to parse enrollment data: $e');
      _enrolledEmbeddings = null;
    }
  }

  /// Process raw PCM audio into a single 96-dim profile embedding.
  /// Called by the setup screen for each enrollment sample.
  Future<List<double>> extractProfileEmbedding(List<double> pcmSamples) async {
    if (_melSession == null || _embeddingSession == null) {
      throw StateError('ONNX models not loaded. Call initialize() first.');
    }

    // Process audio through mel spectrogram in 1280-sample frames
    final List<List<double>> allMelFrames = [];
    int offset = 0;
    while (offset + _frameSamples <= pcmSamples.length) {
      final frame = pcmSamples.sublist(offset, offset + _frameSamples);
      final melFrames = await _computeMelSpectrogram(frame);
      allMelFrames.addAll(melFrames);
      offset += _frameSamples;
    }

    print(
        '[WakeWord] Enrollment: ${allMelFrames.length} mel frames from ${pcmSamples.length} samples');

    // Extract embeddings from sliding windows of 76 mel frames
    final List<List<double>> embeddings = [];
    int melOffset = 0;
    while (melOffset + _melFramesNeeded <= allMelFrames.length) {
      final melWindow =
          allMelFrames.sublist(melOffset, melOffset + _melFramesNeeded);
      final embedding = await _extractEmbedding(melWindow);
      embeddings.add(embedding);
      melOffset += _melSlide;
    }

    if (embeddings.isEmpty) {
      throw StateError('No embeddings extracted. Audio may be too short.');
    }

    print(
        '[WakeWord] Enrollment: ${embeddings.length} embeddings extracted, averaging...');

    // Average all embeddings into one profile vector
    final int dim = embeddings.first.length;
    final List<double> averaged = List.filled(dim, 0.0);
    for (final emb in embeddings) {
      for (int i = 0; i < dim; i++) {
        averaged[i] += emb[i];
      }
    }
    for (int i = 0; i < dim; i++) {
      averaged[i] /= embeddings.length;
    }

    return averaged;
  }

  /// Save enrolled profile embeddings to SharedPreferences.
  Future<void> saveEnrollment(List<List<double>> profileEmbeddings) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(profileEmbeddings);
    await prefs.setString(_enrollmentPrefKey, jsonStr);

    _enrolledEmbeddings = profileEmbeddings;
    print('[WakeWord] Saved ${profileEmbeddings.length} enrolled embeddings');
    notifyListeners();
  }

  /// Clear enrollment data (for re-enrollment).
  Future<void> clearEnrollment() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_enrollmentPrefKey);
    _enrolledEmbeddings = null;
    print('[WakeWord] Enrollment cleared');
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  // AUDIO CAPTURE
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _startListening() async {
    if (_isListening) return;
    if (!_isInitialized) return;

    _recorder = AudioRecorder();

    if (!await _recorder!.hasPermission()) {
      _errorMessage = 'Microphone permission denied';
      print('[WakeWord] No microphone permission');
      notifyListeners();
      return;
    }

    // Clear all buffers for fresh start
    _audioBuffer.clear();
    _melBuffer.clear();
    _embeddingBuffer.clear();
    _frameQueue.clear();
    _predictionCount = 0;
    _isProcessing = false;

    try {
      final stream = await _recorder!.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );

      _audioSubscription = stream.listen(
        _onAudioData,
        onError: (e) => print('[WakeWord] Audio stream error: $e'),
        onDone: () => print('[WakeWord] Audio stream ended'),
      );

      _isListening = true;
      _errorMessage = null;
      print('[WakeWord] Listening started (${_sampleRate}Hz, mono, PCM16)');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to start audio capture';
      print('[WakeWord] Start listening error: $e');
      notifyListeners();
    }
  }

  Future<void> _stopListening() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    try {
      await _recorder?.stop();
    } catch (_) {}

    try {
      await _recorder?.dispose();
    } catch (_) {}
    _recorder = null;

    _isListening = false;
    _isProcessing = false;
    _frameQueue.clear();
  }

  // ═══════════════════════════════════════════════════════════════════
  // AUDIO PROCESSING PIPELINE
  // ═══════════════════════════════════════════════════════════════════

  void _onAudioData(Uint8List data) {
    // Convert 16-bit PCM (little-endian) to float32 normalized to [-1.0, 1.0]
    final byteData = ByteData.sublistView(data);
    final numSamples = data.length ~/ 2;

    for (int i = 0; i < numSamples; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      _audioBuffer.add(sample / 32767.0);
    }

    // Queue complete frames (1280 samples = 80ms each)
    while (_audioBuffer.length >= _frameSamples) {
      final frame = List<double>.from(_audioBuffer.sublist(0, _frameSamples));
      _audioBuffer.removeRange(0, _frameSamples);
      _frameQueue.add(frame);
    }

    // Process queued frames sequentially
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (_frameQueue.isNotEmpty) {
      final frame = _frameQueue.removeAt(0);
      await _processFrame(frame);
    }

    _isProcessing = false;
  }

  Future<void> _processFrame(List<double> audioFrame) async {
    try {
      // ─── Step 1: Audio → Mel Spectrogram ───
      final melFrames = await _computeMelSpectrogram(audioFrame);
      _melBuffer.addAll(melFrames);

      // ─── Step 2: Mel → Embeddings (when enough mel frames accumulated) ───
      while (_melBuffer.length >= _melFramesNeeded) {
        final melWindow = _melBuffer.sublist(0, _melFramesNeeded);
        // Slide forward by 8 frames (80ms)
        _melBuffer.removeRange(0, _melSlide);

        final embedding = await _extractEmbedding(melWindow);
        _embeddingBuffer.add(embedding);

        // Keep only the most recent embeddings needed
        while (_embeddingBuffer.length > _embeddingsNeeded) {
          _embeddingBuffer.removeAt(0);
        }

        // ─── Step 3: Embeddings → Classification ───
        if (_embeddingBuffer.length == _embeddingsNeeded) {
          final score = await _classifyWakeWord();
          _predictionCount++;

          // Skip warmup predictions (model needs to stabilize)
          if (_predictionCount <= _warmupPredictions) {
            print('[WakeWord] Warmup #$_predictionCount score=${score.toStringAsFixed(4)} (skipped)');
            continue;
          }

          // Log periodically for monitoring
          if (_predictionCount % 50 == 0) {
            print('[WakeWord] Prediction #$_predictionCount score=${score.toStringAsFixed(4)}');
          }

          // Detection with cooldown to prevent rapid re-triggers
          if (score > _threshold) {
            final now = DateTime.now();
            if (_lastDetection == null ||
                now.difference(_lastDetection!).inMilliseconds >
                    _detectionCooldownMs) {
              // ─── Cosine Similarity Verification ───
              if (_enrolledEmbeddings != null &&
                  _enrolledEmbeddings!.isNotEmpty) {
                final int dim = _embeddingBuffer.first.length;
                final List<double> currentAvg = List.filled(dim, 0.0);
                for (final emb in _embeddingBuffer) {
                  for (int i = 0; i < dim; i++) {
                    currentAvg[i] += emb[i];
                  }
                }
                for (int i = 0; i < dim; i++) {
                  currentAvg[i] /= _embeddingBuffer.length;
                }

                double bestSimilarity = -1.0;
                for (final enrolled in _enrolledEmbeddings!) {
                  final sim = _cosineSimilarity(currentAvg, enrolled);
                  if (sim > bestSimilarity) bestSimilarity = sim;
                }

                print(
                    '[WakeWord] Similarity: best=${bestSimilarity.toStringAsFixed(4)} threshold=$_similarityThreshold');

                if (bestSimilarity < _similarityThreshold) {
                  print(
                      '[WakeWord] Detection suppressed (similarity too low: ${bestSimilarity.toStringAsFixed(4)})');
                  continue;
                }
              }

              _lastDetection = now;
              print(
                  '[WakeWord] *** WAKE WORD DETECTED! score=${score.toStringAsFixed(4)} ***');
              onWakeWordDetected?.call();
            } else {
              print(
                  '[WakeWord] Detection suppressed (cooldown) score=${score.toStringAsFixed(4)}');
            }
          }
        }
      }
    } catch (e, st) {
      print('[WakeWord] Process frame error: $e');
      print('[WakeWord] Stack: $st');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // ONNX INFERENCE — Stage 1: Mel Spectrogram
  // ═══════════════════════════════════════════════════════════════════

  Future<List<List<double>>> _computeMelSpectrogram(List<double> audioFrame) async {
    // Input: [1, 1280] float32 raw audio samples
    final inputData = Float32List.fromList(audioFrame);
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      inputData,
      [1, _frameSamples],
    );

    final runOptions = OrtRunOptions();
    final outputs = await _melSession!.runAsync(
      runOptions,
      {_melInputName: inputTensor},
    );

    // Output shape: [time, 1, dim2, 32] — extract and normalize mel frames
    final outputTensor = outputs![0]!;
    final rawOutput = outputTensor.value;

    final melFrames = <List<double>>[];

    // Parse 4D output: [time][1][dim][32] → list of 32-element mel frames
    if (rawOutput is List) {
      for (final timeStep in rawOutput) {
        if (timeStep is List) {
          for (final channel in timeStep) {
            if (channel is List) {
              for (final melRow in channel) {
                if (melRow is List) {
                  // Normalize: (value / 10.0) + 2.0 (required for embedding model)
                  final normalized = List<double>.generate(
                    melRow.length,
                    (i) => ((melRow[i] as num).toDouble() / 10.0) + 2.0,
                  );
                  melFrames.add(normalized);
                }
              }
            }
          }
        }
      }
    }

    // Release tensors
    inputTensor.release();
    runOptions.release();
    for (var o in outputs) {
      o?.release();
    }

    return melFrames;
  }

  // ═══════════════════════════════════════════════════════════════════
  // ONNX INFERENCE — Stage 2: Speech Embedding
  // ═══════════════════════════════════════════════════════════════════

  Future<List<double>> _extractEmbedding(List<List<double>> melWindow) async {
    // Input: [1, 76, 32, 1] float32
    // Flatten 76 frames of 32 mel bins into 1D array
    final flatData = Float32List(76 * 32);
    int idx = 0;
    for (final frame in melWindow) {
      for (final val in frame) {
        flatData[idx++] = val;
      }
    }

    final inputTensor = OrtValueTensor.createTensorWithDataList(
      flatData,
      [1, _melFramesNeeded, 32, 1],
    );

    final runOptions = OrtRunOptions();
    final outputs = await _embeddingSession!.runAsync(
      runOptions,
      {_embInputName: inputTensor},
    );

    // Output shape: [1, 1, 1, 96] — extract 96-dim embedding vector
    final outputTensor = outputs![0]!;
    final rawOutput = outputTensor.value;

    final embedding = <double>[];
    _flattenToDoubles(rawOutput, embedding);

    // Release tensors
    inputTensor.release();
    runOptions.release();
    for (var o in outputs) {
      o?.release();
    }

    return embedding;
  }

  // ═══════════════════════════════════════════════════════════════════
  // ONNX INFERENCE — Stage 3: Wake Word Classification
  // ═══════════════════════════════════════════════════════════════════

  Future<double> _classifyWakeWord() async {
    // Input: [1, 16, 96] float32
    final flatData = Float32List(16 * 96);
    int idx = 0;
    for (final emb in _embeddingBuffer) {
      for (final val in emb) {
        flatData[idx++] = val;
      }
    }

    final inputTensor = OrtValueTensor.createTensorWithDataList(
      flatData,
      [1, _embeddingsNeeded, 96],
    );

    final runOptions = OrtRunOptions();
    final outputs = await _wakeWordSession!.runAsync(
      runOptions,
      {_wwInputName: inputTensor},
    );

    // Output shape: [1, 1] — single detection score
    final outputTensor = outputs![0]!;
    final rawOutput = outputTensor.value;

    double score = 0.0;
    if (rawOutput is List && rawOutput.isNotEmpty) {
      final inner = rawOutput[0];
      if (inner is List && inner.isNotEmpty) {
        score = (inner[0] as num).toDouble();
      } else if (inner is num) {
        score = inner.toDouble();
      }
    }

    // Release tensors
    inputTensor.release();
    runOptions.release();
    for (var o in outputs) {
      o?.release();
    }

    return score;
  }

  // ═══════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════

  void _flattenToDoubles(dynamic value, List<double> result) {
    if (value is num) {
      result.add(value.toDouble());
    } else if (value is List) {
      for (final item in value) {
        _flattenToDoubles(item, result);
      }
    }
  }

  /// Cosine similarity between two vectors. Returns [-1, 1].
  static double _cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0.0, magA = 0.0, magB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    magA = sqrt(magA);
    magB = sqrt(magB);
    if (magA == 0 || magB == 0) return 0.0;
    return dot / (magA * magB);
  }

  // ═══════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _stopListening();
    _melSession?.release();
    _embeddingSession?.release();
    _wakeWordSession?.release();
    _melSession = null;
    _embeddingSession = null;
    _wakeWordSession = null;
    _isInitialized = false;
    print('[WakeWord] Disposed');
    super.dispose();
  }
}
