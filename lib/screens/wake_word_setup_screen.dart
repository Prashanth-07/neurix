import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../services/wake_word_service.dart';
import '../utils/constants.dart';
import '../widgets/starfield_background.dart';

/// Voice enrollment screen for "Hey Neurix" wake word setup.
/// Records 5 samples of the user saying "Hey Neurix",
/// extracts 96-dim speech embeddings + 16-frame sequences via the ONNX pipeline,
/// and stores them for sequence-similarity verification.
class WakeWordSetupScreen extends StatefulWidget {
  const WakeWordSetupScreen({Key? key}) : super(key: key);

  @override
  State<WakeWordSetupScreen> createState() => _WakeWordSetupScreenState();
}

class _WakeWordSetupScreenState extends State<WakeWordSetupScreen>
    with TickerProviderStateMixin {
  static const int _totalSamples = WakeWordService.enrollmentSamples;
  static const int _recordDurationMs = 3500;

  final WakeWordService _wakeWordService = WakeWordService();
  AudioRecorder? _recorder;
  bool _modelsReady = false;
  bool _isRecording = false;
  bool _hasStarted = false;

  // Collected enrollment data per sample
  final List<List<double>> _collectedEmbeddings = [];
  final List<List<List<double>>> _collectedSequences = [];
  final List<double> _collectedScores = [];
  final List<List<double>> _collectedRawAudio = [];

  int get _currentStep => _collectedEmbeddings.length;
  String _statusMessage = '';
  bool _isSaving = false;
  bool _showSuccess = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _initModels();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    try {
      _recorder?.stop();
      _recorder?.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _initModels() async {
    print('[WakeWordSetup] Checking ONNX models...');
    if (!_wakeWordService.isInitialized) {
      await _wakeWordService.initialize();
    }
    if (mounted) {
      setState(() {
        _modelsReady = _wakeWordService.isInitialized;
        _statusMessage =
            _modelsReady ? 'Tap the mic to begin' : 'Could not load voice models';
      });
    }
    print('[WakeWordSetup] Models ready: $_modelsReady');
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isSaving || _showSuccess || !_modelsReady) return;

    // Pause wake word listening during enrollment
    if (_wakeWordService.isListening) {
      await _wakeWordService.pause();
    }

    _recorder = AudioRecorder();
    if (!await _recorder!.hasPermission()) {
      if (mounted) {
        setState(() => _statusMessage = 'Microphone permission denied');
      }
      return;
    }

    setState(() {
      _isRecording = true;
      _statusMessage = 'Listening...';
    });

    // Collect raw PCM audio
    final List<double> pcmSamples = [];

    final stream = await _recorder!.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    final subscription = stream.listen((Uint8List data) {
      final byteData = ByteData.sublistView(data);
      final numSamples = data.length ~/ 2;
      for (int i = 0; i < numSamples; i++) {
        final sample = byteData.getInt16(i * 2, Endian.little);
        pcmSamples.add(sample / 32767.0);
      }
    });

    // Wait for recording duration
    await Future.delayed(const Duration(milliseconds: _recordDurationMs));

    // Stop recording
    await subscription.cancel();
    try {
      await _recorder!.stop();
      await _recorder!.dispose();
    } catch (_) {}
    _recorder = null;

    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _statusMessage = 'Processing...';
    });

    print(
        '[WakeWordSetup] Recorded ${pcmSamples.length} samples for step ${_currentStep + 1}');

    // Process through ONNX pipeline — extract full enrollment data
    try {
      final result =
          await _wakeWordService.extractEnrollmentData(pcmSamples);

      // Reject samples where classifier didn't recognize "Hey Neurix"
      if (result.classifierScore < WakeWordService.minEnrollmentScore) {
        print(
            '[WakeWordSetup] Sample REJECTED: score=${result.classifierScore.toStringAsFixed(4)} < ${WakeWordService.minEnrollmentScore}');
        if (mounted) {
          setState(() => _statusMessage = 'Didn\'t catch that. Try again...');
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted &&
                !_isRecording &&
                !_isSaving &&
                _currentStep < _totalSamples) {
              _startRecording();
            }
          });
        }
        return;
      }

      _onSampleCaptured(result, pcmSamples);
    } catch (e) {
      print('[WakeWordSetup] Embedding error: $e');
      if (mounted) {
        setState(() => _statusMessage = 'Could not process. Try again...');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted &&
              !_isRecording &&
              !_isSaving &&
              _currentStep < _totalSamples) {
            _startRecording();
          }
        });
      }
    }
  }

  void _onSampleCaptured(
      EnrollmentSampleResult result, List<double> rawAudio) {
    print(
        '[WakeWordSetup] Sample ${_currentStep + 1}: '
        '${result.averagedEmbedding.length}-dim embedding, '
        'score=${result.classifierScore.toStringAsFixed(4)}, '
        'sequence=${result.embeddingSequence.length}x${result.embeddingSequence.first.length}');

    setState(() {
      _collectedEmbeddings.add(result.averagedEmbedding);
      _collectedSequences.add(result.embeddingSequence);
      _collectedScores.add(result.classifierScore);
      _collectedRawAudio.add(rawAudio);
      _statusMessage = 'Got it!';
    });

    _progressController.animateTo(
      _currentStep / _totalSamples,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );

    if (_currentStep >= _totalSamples) {
      _finishSetup();
    } else {
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted &&
            !_isRecording &&
            !_isSaving &&
            _currentStep < _totalSamples) {
          _startRecording();
        }
      });
    }
  }

  Future<void> _finishSetup() async {
    setState(() {
      _isSaving = true;
      _statusMessage = 'Saving your voice profile...';
    });

    _progressController.animateTo(1.0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);

    // Save full enrollment data: embeddings, sequences, scores, raw audio
    await _wakeWordService.saveEnrollmentFull(
      averagedEmbeddings: _collectedEmbeddings,
      sequences: _collectedSequences,
      classifierScores: _collectedScores,
      rawAudioSamples: _collectedRawAudio,
    );

    setState(() {
      _isSaving = false;
      _showSuccess = true;
      _statusMessage = '"Hey Neurix" is ready!';
    });

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _onMicTap() {
    if (!_modelsReady || _isSaving || _showSuccess) return;

    if (!_hasStarted) {
      setState(() => _hasStarted = true);
      _startRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: StarfieldBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // Title
                  const Text(
                    'Set Up\n"Hey Neurix"',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Subtitle
                  Text(
                    _hasStarted
                        ? 'Say "Hey Neurix" clearly'
                        : 'Say "Hey Neurix" $_totalSamples times so\nNeurix can learn your voice.',
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const Spacer(flex: 2),

                  // Mic button with progress ring — centered
                  _buildMicWithProgress(),
                  const SizedBox(height: 28),

                  // Step counter
                  Text(
                    _showSuccess
                        ? 'Complete!'
                        : _hasStarted
                            ? '$_currentStep of $_totalSamples'
                            : 'Tap the mic to begin',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color:
                          _showSuccess ? AppColors.success : AppColors.primaryLight,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Status text
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _statusMessage,
                      key: ValueKey(_statusMessage),
                      style: TextStyle(
                        fontSize: 16,
                        color: _showSuccess
                            ? AppColors.success
                            : _isRecording
                                ? const Color(0xFFEF4444)
                                : AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMicWithProgress() {
    const double size = 140;
    const double strokeWidth = 5.0;

    return GestureDetector(
      onTap: (!_hasStarted && _modelsReady) ? _onMicTap : null,
      child: SizedBox(
        width: size + strokeWidth * 2,
        height: size + strokeWidth * 2,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background ring (track)
            SizedBox(
              width: size + strokeWidth,
              height: size + strokeWidth,
              child: CircularProgressIndicator(
                value: 1.0,
                strokeWidth: strokeWidth,
                color: AppColors.glass,
              ),
            ),

            // Animated progress ring
            AnimatedBuilder(
              animation: _progressController,
              builder: (context, child) {
                return SizedBox(
                  width: size + strokeWidth,
                  height: size + strokeWidth,
                  child: CircularProgressIndicator(
                    value: _progressController.value,
                    strokeWidth: strokeWidth,
                    color:
                        _showSuccess ? AppColors.success : AppColors.primaryLight,
                    strokeCap: StrokeCap.round,
                  ),
                );
              },
            ),

            // Mic button
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                final scale = _isRecording ? _pulseAnimation.value : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: size - 10,
                    height: size - 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: _showSuccess
                            ? [
                                AppColors.success,
                                AppColors.success.withOpacity(0.8)
                              ]
                            : _isRecording
                                ? [
                                    const Color(0xFFEF4444),
                                    const Color(0xFFDC2626)
                                  ]
                                : _isSaving
                                    ? [
                                        AppColors.warning,
                                        const Color(0xFFD97706)
                                      ]
                                    : [
                                        AppColors.primaryLight,
                                        AppColors.primary
                                      ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_showSuccess
                                  ? AppColors.success
                                  : _isRecording
                                      ? const Color(0xFFEF4444)
                                      : AppColors.primary)
                              .withOpacity(0.35),
                          blurRadius: _isRecording ? 35 : 20,
                          spreadRadius: _isRecording ? 6 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _showSuccess
                          ? Icons.check_rounded
                          : _isRecording
                              ? Icons.hearing_rounded
                              : _isSaving
                                  ? Icons.hourglass_top_rounded
                                  : Icons.mic_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
