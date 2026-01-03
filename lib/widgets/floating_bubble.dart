import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

enum BubbleState { idle, recording, processing, response }

class FloatingBubble extends StatefulWidget {
  const FloatingBubble({super.key});

  @override
  State<FloatingBubble> createState() => _FloatingBubbleState();
}

class _FloatingBubbleState extends State<FloatingBubble>
    with SingleTickerProviderStateMixin {
  BubbleState _state = BubbleState.idle;
  String _transcribedText = '';
  String _responseText = '';
  bool _isExpanded = false;

  // Bubble size constants
  static const double collapsedSize = 60.0;
  static const double expandedSize = 200.0;
  static const int overlayCollapsedSize = 100;  // Match overlay_service.dart
  static const int overlayExpandedSize = 220;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _speechInitialized = false;

  Timer? _autoHideTimer;
  Timer? _silenceTimer;
  DateTime? _lastSpeechTime;

  @override
  void initState() {
    super.initState();
    _initPulseAnimation();
    _initSpeech();
    _initTts();
  }

  void _initPulseAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  Future<void> _initSpeech() async {
    _speechInitialized = await _speech.initialize(
      onStatus: (status) {
        print('[Bubble] Speech status: $status');
        // Auto-stop when speech recognition detects end of speech
        if (status == 'done' || status == 'notListening') {
          if (_state == BubbleState.recording) {
            _silenceTimer?.cancel();
            if (_transcribedText.isNotEmpty) {
              _processInput();
            } else {
              // No speech detected, collapse overlay
              _collapseOverlay();
            }
          }
        }
      },
      onError: (error) {
        print('[Bubble] Speech error: $error');
        _silenceTimer?.cancel();
        _collapseOverlay();
      },
    );
    print('[Bubble] Speech initialized: $_speechInitialized');
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _autoHideTimer?.cancel();
    _silenceTimer?.cancel();
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }

  void _onTap() {
    if (_state == BubbleState.idle) {
      _startRecording();
    } else if (_state == BubbleState.response) {
      // Tap to dismiss response early
      _collapseOverlay();
      _autoHideTimer?.cancel();
    }
  }

  Future<void> _expandOverlay() async {
    try {
      await FlutterOverlayWindow.resizeOverlay(
        overlayExpandedSize,
        overlayExpandedSize,
        true,
      );
    } catch (e) {
      print('[Bubble] Error expanding overlay: $e');
    }
  }

  Future<void> _collapseOverlay() async {
    try {
      await FlutterOverlayWindow.resizeOverlay(
        overlayCollapsedSize,
        overlayCollapsedSize,
        true,
      );
    } catch (e) {
      print('[Bubble] Error collapsing overlay: $e');
    }
    setState(() {
      _state = BubbleState.idle;
      _isExpanded = false;
      _transcribedText = '';
      _responseText = '';
    });
  }

  Future<void> _startRecording() async {
    if (!_speechInitialized) {
      await _initSpeech();
    }

    // Expand overlay (visual only, no resize needed)
    _expandOverlay();

    setState(() {
      _state = BubbleState.recording;
      _isExpanded = true;
      _transcribedText = '';
      _responseText = '';
    });

    _lastSpeechTime = DateTime.now();

    // Start silence detection timer - stops after 5 seconds of no speech
    _startSilenceDetection();

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _transcribedText = result.recognizedWords;
        });
        // Update last speech time when we get new words
        if (result.recognizedWords.isNotEmpty) {
          _lastSpeechTime = DateTime.now();
        }

        // If final result is received, process it
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          _silenceTimer?.cancel();
          _speech.stop();
          _processInput();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5), // Wait 5 seconds for pause
      localeId: 'en_US',
    );
  }

  void _startSilenceDetection() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_state != BubbleState.recording) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final silenceDuration = now.difference(_lastSpeechTime ?? now);

      // If 5 seconds passed with no speech
      if (silenceDuration.inSeconds >= 5) {
        timer.cancel();
        _speech.stop();

        if (_transcribedText.isNotEmpty) {
          _processInput();
        } else {
          // No speech at all, collapse overlay
          _collapseOverlay();
        }
      }
    });
  }

  Future<void> _processInput() async {
    setState(() {
      _state = BubbleState.processing;
    });

    print('[Bubble] Processing input: $_transcribedText');

    try {
      // Detect intent and process
      final intent = _detectIntent(_transcribedText);
      print('[Bubble] Detected intent: $intent');

      String response;
      if (intent == 'unclear') {
        response = 'Did you want to save this as a memory or search for something?';
      } else {
        // Send to main app for processing
        await FlutterOverlayWindow.shareData({
          'action': intent,
          'text': _transcribedText,
        });

        // Wait for response from main app
        response = await _waitForResponse(intent);
      }

      setState(() {
        _state = BubbleState.response;
        _responseText = response;
      });

      // Speak the response
      await _tts.speak(response);

      // Auto-hide after 5 seconds (collapse overlay)
      _autoHideTimer?.cancel();
      _autoHideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          _collapseOverlay();
        }
      });
    } catch (e) {
      print('[Bubble] Error processing: $e');
      setState(() {
        _state = BubbleState.response;
        _responseText = 'Sorry, something went wrong. Please try again.';
      });
      await _tts.speak(_responseText);

      _autoHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          _collapseOverlay();
        }
      });
    }
  }

  String _detectIntent(String text) {
    final lowerText = text.toLowerCase().trim();

    // Save/Add memory patterns
    final savePatterns = [
      'remember',
      'save',
      'store',
      'note',
      'keep in mind',
      'don\'t forget',
      'i left',
      'i put',
      'i placed',
      'i kept',
      'i stored',
      'my password',
      'my pin',
      'meeting at',
      'meeting is',
      'appointment',
    ];

    // Search patterns
    final searchPatterns = [
      'where is',
      'where are',
      'where did',
      'what is',
      'what was',
      'what\'s',
      'when is',
      'when was',
      'find',
      'search',
      'look for',
      'do i have',
      'did i',
      'how many',
      'tell me',
    ];

    for (var pattern in savePatterns) {
      if (lowerText.contains(pattern)) {
        return 'add';
      }
    }

    for (var pattern in searchPatterns) {
      if (lowerText.contains(pattern)) {
        return 'search';
      }
    }

    // If unclear, default to search if it's a question, otherwise add
    if (lowerText.endsWith('?')) {
      return 'search';
    }

    return 'unclear';
  }

  Future<String> _waitForResponse(String intent) async {
    // Listen for response from main app with timeout
    final completer = Completer<String>();
    StreamSubscription? subscription;

    // Set up listener for response
    subscription = FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is Map<String, dynamic> && data['type'] == 'response') {
        final responseText = data['text'] as String?;
        if (responseText != null && !completer.isCompleted) {
          completer.complete(responseText);
          subscription?.cancel();
        }
      }
    });

    // Timeout after 30 seconds
    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        subscription?.cancel();
        if (intent == 'add') {
          completer.complete('Memory saved!');
        } else {
          completer.complete('Search completed.');
        }
      }
    });

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final currentSize = _isExpanded ? expandedSize : collapsedSize;
    final currentOverlaySize = _isExpanded ? overlayExpandedSize.toDouble() : overlayCollapsedSize.toDouble();

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: _onTap,
        child: Container(
          width: currentOverlaySize,
          height: currentOverlaySize,
          // Align bubble to left so it stays visible when overlay is on right edge
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: currentSize,
            height: currentSize,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _getGradientColors(),
              ),
              borderRadius: BorderRadius.circular(_isExpanded ? 20 : 30),
              boxShadow: [
                BoxShadow(
                  color: _getBubbleColor().withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  List<Color> _getGradientColors() {
    switch (_state) {
      case BubbleState.idle:
        return [Colors.deepPurple.shade400, Colors.deepPurple.shade700];
      case BubbleState.recording:
        return [Colors.red.shade400, Colors.red.shade700];
      case BubbleState.processing:
        return [Colors.orange.shade400, Colors.orange.shade700];
      case BubbleState.response:
        return [Colors.green.shade400, Colors.green.shade700];
    }
  }

  Color _getBubbleColor() {
    switch (_state) {
      case BubbleState.idle:
        return Colors.deepPurple.withValues(alpha: 0.8);
      case BubbleState.recording:
        return Colors.red.withValues(alpha: 0.9);
      case BubbleState.processing:
        return Colors.orange.withValues(alpha: 0.9);
      case BubbleState.response:
        return Colors.green.withValues(alpha: 0.9);
    }
  }

  Widget _buildContent() {
    switch (_state) {
      case BubbleState.idle:
        return _buildIdleContent();
      case BubbleState.recording:
        return _buildRecordingContent();
      case BubbleState.processing:
        return _buildProcessingContent();
      case BubbleState.response:
        return _buildResponseContent();
    }
  }

  Widget _buildIdleContent() {
    return const Center(
      child: Icon(
        Icons.mic,
        color: Colors.white,
        size: 30,
      ),
    );
  }

  Widget _buildRecordingContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: const Icon(
                  Icons.mic,
                  color: Colors.white,
                  size: 40,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            _transcribedText.isEmpty ? 'Listening...' : _transcribedText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _transcribedText,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Processing...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponseContent() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Text(
              _responseText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
