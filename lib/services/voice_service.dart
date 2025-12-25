import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

enum VoiceState {
  stopped,
  listening,
  speaking,
  processing,
}

class VoiceService extends ChangeNotifier {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  
  VoiceState _state = VoiceState.stopped;
  String _recognizedText = '';
  String _errorMessage = '';
  bool _isInitialized = false;
  double _confidence = 0.0;
  
  VoiceState get state => _state;
  String get recognizedText => _recognizedText;
  String get errorMessage => _errorMessage;
  bool get isInitialized => _isInitialized;
  double get confidence => _confidence;
  
  bool get isListening => _state == VoiceState.listening;
  bool get isSpeaking => _state == VoiceState.speaking;
  bool get isProcessing => _state == VoiceState.processing;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Request microphone permission
      final micPermission = await Permission.microphone.request();
      if (!micPermission.isGranted) {
        _errorMessage = 'Microphone permission is required for voice input';
        notifyListeners();
        return;
      }
      
      // Initialize speech-to-text
      final sttAvailable = await _speechToText.initialize(
        onError: _onSpeechError,
        onStatus: _onSpeechStatus,
      );
      
      if (!sttAvailable) {
        _errorMessage = 'Speech recognition is not available on this device';
        notifyListeners();
        return;
      }
      
      // Initialize text-to-speech
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);
      
      // Set TTS completion handler
      _flutterTts.setCompletionHandler(() {
        _setState(VoiceState.stopped);
      });
      
      _isInitialized = true;
      _errorMessage = '';
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to initialize voice service: ${e.toString()}';
      notifyListeners();
    }
  }
  
  Future<void> startListening({
    String? localeId,
    Duration? listenFor,
    Duration? pauseFor,
  }) async {
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) return;
    }
    
    if (_state == VoiceState.listening) return;
    
    _recognizedText = '';
    _confidence = 0.0;
    _errorMessage = '';
    _setState(VoiceState.listening);
    
    try {
      await _speechToText.listen(
        onResult: _onSpeechResult,
        localeId: localeId ?? 'en_US',
        listenFor: listenFor ?? const Duration(seconds: 30),
        pauseFor: pauseFor ?? const Duration(seconds: 3),
        cancelOnError: false,
        partialResults: true,
      );
    } catch (e) {
      _errorMessage = 'Failed to start listening: ${e.toString()}';
      _setState(VoiceState.stopped);
    }
  }
  
  Future<void> stopListening() async {
    if (_state != VoiceState.listening) return;
    
    try {
      await _speechToText.stop();
      _setState(VoiceState.stopped);
    } catch (e) {
      _errorMessage = 'Failed to stop listening: ${e.toString()}';
      _setState(VoiceState.stopped);
    }
  }
  
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      await initialize();
      if (!_isInitialized) return;
    }
    
    if (_state == VoiceState.speaking) {
      await _flutterTts.stop();
    }
    
    _setState(VoiceState.speaking);
    
    try {
      await _flutterTts.speak(text);
    } catch (e) {
      _errorMessage = 'Failed to speak: ${e.toString()}';
      _setState(VoiceState.stopped);
    }
  }
  
  Future<void> stopSpeaking() async {
    if (_state != VoiceState.speaking) return;
    
    try {
      await _flutterTts.stop();
      _setState(VoiceState.stopped);
    } catch (e) {
      _errorMessage = 'Failed to stop speaking: ${e.toString()}';
      _setState(VoiceState.stopped);
    }
  }
  
  void _onSpeechResult(SpeechRecognitionResult result) {
    _recognizedText = result.recognizedWords;
    _confidence = result.confidence;
    notifyListeners();
  }
  
  void _onSpeechError(dynamic error) {
    print('Speech error: $error');
    _errorMessage = 'Speech recognition error: ${error.toString()}';
    _setState(VoiceState.stopped);
  }

  void _onSpeechStatus(String status) {
    print('Speech status: $status');

    if (status == 'notListening' || status == 'done') {
      if (_recognizedText.isEmpty) {
        print('No speech detected - microphone may not be working on emulator');
      }
      _setState(VoiceState.stopped);
    }
  }
  
  void _setState(VoiceState newState) {
    _state = newState;
    notifyListeners();
  }
  
  void setProcessing(bool processing) {
    _setState(processing ? VoiceState.processing : VoiceState.stopped);
  }
  
  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }
  
  void clearRecognizedText() {
    _recognizedText = '';
    _confidence = 0.0;
    notifyListeners();
  }
  
  @override
  void dispose() {
    _speechToText.cancel();
    _flutterTts.stop();
    super.dispose();
  }
}
