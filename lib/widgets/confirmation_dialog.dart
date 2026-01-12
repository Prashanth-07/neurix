import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

/// Confirmation dialog for save memory and reminder intents
/// Shows transcribed text, speaks it aloud, listens for yes/no voice input
/// Auto-confirms after 5 seconds if no input received
class ConfirmationDialog extends StatefulWidget {
  final String intent; // 'save' or 'reminder'
  final String transcribedText;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const ConfirmationDialog({
    Key? key,
    required this.intent,
    required this.transcribedText,
    required this.onConfirm,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<ConfirmationDialog> createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<ConfirmationDialog> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  Timer? _autoConfirmTimer;
  bool _isListeningForConfirmation = false;
  bool _hasResponded = false;
  String _listeningStatus = '';

  // Voice keywords for yes/no
  static const List<String> _yesKeywords = ['yes', 'yeah', 'yep', 'confirm', 'ok', 'okay', 'sure', 'yup', 'affirmative'];
  static const List<String> _noKeywords = ['no', 'nope', 'cancel', 'don\'t', 'stop', 'negative', 'never'];

  @override
  void initState() {
    super.initState();
    _initTts();
    _startConfirmationFlow();
  }

  @override
  void dispose() {
    _autoConfirmTimer?.cancel();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  String get _dialogMessage {
    if (widget.intent == 'save') {
      return 'Do you want to save this memory: "${widget.transcribedText}"';
    } else {
      return 'Do you want to set this reminder: "${widget.transcribedText}"';
    }
  }

  Future<void> _startConfirmationFlow() async {
    print('[ConfirmDialog] Starting confirmation flow for intent: ${widget.intent}');
    print('[ConfirmDialog] Message: $_dialogMessage');

    // Speak the confirmation message
    await _tts.speak(_dialogMessage);

    // Wait for TTS to finish before starting to listen
    _tts.setCompletionHandler(() {
      if (!_hasResponded && mounted) {
        _startListeningForYesNo();
        _startAutoConfirmTimer();
      }
    });
  }

  void _startAutoConfirmTimer() {
    print('[ConfirmDialog] Starting 5-second auto-confirm timer');
    _autoConfirmTimer = Timer(const Duration(seconds: 5), () {
      if (!_hasResponded && mounted) {
        print('[ConfirmDialog] Auto-confirming after timeout');
        _handleConfirm();
      }
    });
  }

  Future<void> _startListeningForYesNo() async {
    print('[ConfirmDialog] Starting to listen for yes/no');

    bool available = await _speech.initialize(
      onStatus: (status) {
        print('[ConfirmDialog] Speech status: $status');
        if (mounted) {
          setState(() {
            _listeningStatus = status;
          });
        }
      },
      onError: (error) {
        print('[ConfirmDialog] Speech error: $error');
      },
    );

    if (!available) {
      print('[ConfirmDialog] Speech recognition not available');
      return;
    }

    setState(() {
      _isListeningForConfirmation = true;
    });

    await _speech.listen(
      onResult: (result) {
        print('[ConfirmDialog] Heard: "${result.recognizedWords}" (final: ${result.finalResult})');

        final words = result.recognizedWords.toLowerCase().trim();

        // Check for yes keywords
        for (final keyword in _yesKeywords) {
          if (words.contains(keyword)) {
            print('[ConfirmDialog] Detected YES keyword: $keyword');
            _handleConfirm();
            return;
          }
        }

        // Check for no keywords
        for (final keyword in _noKeywords) {
          if (words.contains(keyword)) {
            print('[ConfirmDialog] Detected NO keyword: $keyword');
            _handleCancel();
            return;
          }
        }
      },
      listenFor: const Duration(seconds: 6),
      pauseFor: const Duration(seconds: 3),
      localeId: 'en_US',
    );
  }

  void _handleConfirm() {
    if (_hasResponded) return;
    _hasResponded = true;

    print('[ConfirmDialog] CONFIRMED');
    _autoConfirmTimer?.cancel();
    _speech.stop();

    Navigator.of(context).pop();
    widget.onConfirm();
  }

  void _handleCancel() {
    if (_hasResponded) return;
    _hasResponded = true;

    print('[ConfirmDialog] CANCELLED');
    _autoConfirmTimer?.cancel();
    _speech.stop();

    Navigator.of(context).pop();
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon based on intent
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: widget.intent == 'save'
                    ? Colors.amber.withOpacity(0.15)
                    : Colors.deepPurple.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.intent == 'save'
                    ? Icons.lightbulb_outline
                    : Icons.notifications_outlined,
                size: 32,
                color: widget.intent == 'save'
                    ? Colors.amber[700]
                    : Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 16),

            // Static text: "Do you want to..."
            Text(
              widget.intent == 'save'
                  ? 'Do you want to save this memory:'
                  : 'Do you want to set this reminder:',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Transcribed text in quotes
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '"${widget.transcribedText}"',
                style: TextStyle(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

            // Listening indicator
            if (_isListeningForConfirmation)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.deepPurple.withOpacity(0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Listening... (say "yes" or "no")',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),

            // Buttons
            Row(
              children: [
                // No button
                Expanded(
                  child: OutlinedButton(
                    onPressed: _handleCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.grey[400]!),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'No',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Yes button (highlighted as default)
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _handleConfirm,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.deepPurple,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Yes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the confirmation dialog and returns true if confirmed, false if cancelled
Future<bool> showConfirmationDialog({
  required BuildContext context,
  required String intent,
  required String transcribedText,
}) async {
  final completer = Completer<bool>();

  showDialog(
    context: context,
    barrierDismissible: false, // Prevent dismissing by tapping outside
    builder: (context) => ConfirmationDialog(
      intent: intent,
      transcribedText: transcribedText,
      onConfirm: () => completer.complete(true),
      onCancel: () => completer.complete(false),
    ),
  );

  return completer.future;
}
