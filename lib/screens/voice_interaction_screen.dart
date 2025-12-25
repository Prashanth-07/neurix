import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/voice_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/llm_service.dart';
import '../services/embedding_service.dart';
import '../models/memory_model.dart';

enum VoiceMode { addMemory, search }

class VoiceInteractionScreen extends StatefulWidget {
  const VoiceInteractionScreen({Key? key}) : super(key: key);

  @override
  State<VoiceInteractionScreen> createState() => _VoiceInteractionScreenState();
}

class _VoiceInteractionScreenState extends State<VoiceInteractionScreen> {
  VoiceMode _selectedMode = VoiceMode.addMemory;
  final TextEditingController _textController = TextEditingController();
  final LocalDbService _localDbService = LocalDbService();
  final EmbeddingService _embeddingService = EmbeddingService();
  String _searchResult = '';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VoiceService>().initialize();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _onModeChanged(VoiceMode mode) {
    setState(() {
      _selectedMode = mode;
      _searchResult = '';
    });
    _clearText();
  }

  void _clearText() {
    _textController.clear();
    context.read<VoiceService>().clearRecognizedText();
  }

  void _onVoiceResult(String text) {
    setState(() {
      _textController.text = text;
    });
  }

  Future<void> _startListening() async {
    final voiceService = context.read<VoiceService>();
    voiceService.clearError();
    await voiceService.startListening();
  }

  Future<void> _stopListening() async {
    final voiceService = context.read<VoiceService>();
    await voiceService.stopListening();
  }

  Future<void> _processInput() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final voiceService = context.read<VoiceService>();
      voiceService.setProcessing(true);

      if (_selectedMode == VoiceMode.addMemory) {
        await _addMemory(text);
      } else {
        await _searchMemories(text);
      }
    } catch (e) {
      _showError('Failed to process input: ${e.toString()}');
    } finally {
      setState(() {
        _isProcessing = false;
      });
      context.read<VoiceService>().setProcessing(false);
    }
  }

  Future<void> _addMemory(String content) async {
    try {
      // Get current user ID
      final authService = context.read<AuthService>();
      final userId = authService.currentUser?.uid ?? 'anonymous';

      // Generate embedding for the memory content
      print('Generating embedding for memory...');
      final embedding = await _embeddingService.generateEmbedding(content, isQuery: false);
      print('Embedding generated with ${embedding.length} dimensions');

      final memory = Memory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        content: content,
        createdAt: DateTime.now(),
        userId: userId,
        embedding: embedding,
      );

      // Save memory to local SQLite database (with embedding)
      final success = await _localDbService.saveMemory(memory);

      if (success) {
        final confirmationMessage = 'Memory added successfully: "$content"';
        await context.read<VoiceService>().speak(confirmationMessage);

        _showSuccess('Memory added successfully!');
        _clearText();
      } else {
        _showError('Failed to save memory');
      }
    } catch (e) {
      _showError('Failed to add memory: ${e.toString()}');
    }
  }

  Future<void> _searchMemories(String query) async {
    try {
      print('═══════════════════════════════════════════════════════');
      print('🔍 SEARCH STARTED');
      print('═══════════════════════════════════════════════════════');
      print('📝 Query: "$query"');

      // Step 1: Get user ID
      final authService = context.read<AuthService>();
      final userId = authService.currentUser?.uid ?? 'anonymous';
      print('👤 User ID: $userId');

      // Step 2: Generate embedding for the query
      print('───────────────────────────────────────────────────────');
      print('⏳ Step 2: Generating query embedding...');
      final queryEmbedding = await _embeddingService.generateEmbedding(query, isQuery: true);
      print('✅ Query embedding: ${queryEmbedding.length} dimensions');

      // Step 3: Semantic search
      print('───────────────────────────────────────────────────────');
      print('⏳ Step 3: Semantic search (cosine similarity)...');
      List<Memory> memories = await _localDbService.semanticSearchMemories(
        userId,
        queryEmbedding,
        topK: 5,
        similarityThreshold: 0.2,
      );
      print('✅ Semantic search found: ${memories.length} memories');

      // Step 4: Fallback to keyword search if needed
      if (memories.isEmpty) {
        print('───────────────────────────────────────────────────────');
        print('⏳ Step 4: Fallback to keyword search...');
        memories = await _localDbService.searchMemories(userId, query);
        print('✅ Keyword search found: ${memories.length} memories');
      }

      // Step 5: Generate LLM response
      print('───────────────────────────────────────────────────────');
      String response;
      if (memories.isEmpty) {
        print('❌ No memories found');
        response = 'No memories found related to your query.';
      } else {
        print('⏳ Step 5: Generating LLM response...');
        print('📚 Memories being sent to LLM:');
        for (int i = 0; i < memories.length; i++) {
          print('   ${i + 1}. "${memories[i].content}"');
        }
        final llmService = context.read<LLMService>();
        response = await llmService.generateContextualResponse(query, memories);
        print('✅ LLM Response: "$response"');
      }

      // Step 6: Display and speak
      print('───────────────────────────────────────────────────────');
      print('🔊 Step 6: Speaking response...');
      setState(() {
        _searchResult = response;
      });
      await context.read<VoiceService>().speak(response);

      print('═══════════════════════════════════════════════════════');
      print('✅ SEARCH COMPLETED');
      print('═══════════════════════════════════════════════════════');

    } catch (e) {
      print('❌ SEARCH ERROR: $e');
      _showError('Failed to search memories: ${e.toString()}');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Interaction'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Consumer<VoiceService>(
        builder: (context, voiceService, child) {
          // Update text controller when voice recognition updates
          if (voiceService.recognizedText != _textController.text) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _onVoiceResult(voiceService.recognizedText);
            });
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Mode Selection
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Mode',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: RadioListTile<VoiceMode>(
                                title: const Text('Add Memory'),
                                value: VoiceMode.addMemory,
                                groupValue: _selectedMode,
                                onChanged: (VoiceMode? value) {
                                  if (value != null) _onModeChanged(value);
                                },
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<VoiceMode>(
                                title: const Text('Search'),
                                value: VoiceMode.search,
                                groupValue: _selectedMode,
                                onChanged: (VoiceMode? value) {
                                  if (value != null) _onModeChanged(value);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Voice Status
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getStatusIcon(voiceService.state),
                              color: _getStatusColor(voiceService.state),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getStatusText(voiceService.state),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                        if (voiceService.errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            voiceService.errorMessage,
                            style: TextStyle(color: Colors.red[700]),
                          ),
                        ],
                        if (voiceService.confidence > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Confidence: ${(voiceService.confidence * 100).toStringAsFixed(1)}%',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Text Input
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedMode == VoiceMode.addMemory
                              ? 'Memory Content'
                              : 'Search Query',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _textController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: _selectedMode == VoiceMode.addMemory
                                ? 'Speak or type your memory...'
                                : 'Speak or type your search query...',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Voice Controls
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: voiceService.isListening ? _stopListening : _startListening,
                        icon: Icon(voiceService.isListening ? Icons.mic_off : Icons.mic),
                        label: Text(voiceService.isListening ? 'Stop Listening' : 'Start Listening'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: voiceService.isListening ? Colors.red : Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing || _textController.text.trim().isEmpty
                            ? null
                            : _processInput,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_selectedMode == VoiceMode.addMemory ? Icons.save : Icons.search),
                        label: Text(_selectedMode == VoiceMode.addMemory ? 'Add Memory' : 'Search'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Search Results
                if (_selectedMode == VoiceMode.search && _searchResult.isNotEmpty)
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Search Result',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.volume_up),
                                  onPressed: () => context.read<VoiceService>().speak(_searchResult),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Text(
                                  _searchResult,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _getStatusIcon(VoiceState state) {
    switch (state) {
      case VoiceState.listening:
        return Icons.mic;
      case VoiceState.speaking:
        return Icons.volume_up;
      case VoiceState.processing:
        return Icons.hourglass_empty;
      case VoiceState.stopped:
        return Icons.mic_none;
    }
  }

  Color _getStatusColor(VoiceState state) {
    switch (state) {
      case VoiceState.listening:
        return Colors.red;
      case VoiceState.speaking:
        return Colors.blue;
      case VoiceState.processing:
        return Colors.orange;
      case VoiceState.stopped:
        return Colors.grey;
    }
  }

  String _getStatusText(VoiceState state) {
    switch (state) {
      case VoiceState.listening:
        return 'Listening...';
      case VoiceState.speaking:
        return 'Speaking...';
      case VoiceState.processing:
        return 'Processing...';
      case VoiceState.stopped:
        return 'Ready';
    }
  }
}
