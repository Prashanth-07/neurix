import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/embedding_service.dart';
import '../models/memory_model.dart';
import '../utils/constants.dart';

class AllMemoriesScreen extends StatefulWidget {
  const AllMemoriesScreen({Key? key}) : super(key: key);

  @override
  State<AllMemoriesScreen> createState() => _AllMemoriesScreenState();
}

class _AllMemoriesScreenState extends State<AllMemoriesScreen> {
  final LocalDbService _localDbService = LocalDbService();
  final EmbeddingService _embeddingService = EmbeddingService();
  final TextEditingController _memoryController = TextEditingController();
  List<Memory> _memories = [];
  bool _isLoading = true;
  bool _isAddingMemory = false;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  @override
  void dispose() {
    _memoryController.dispose();
    super.dispose();
  }

  Future<void> _loadMemories() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authService = context.read<AuthService>();
      final userId = authService.currentUser?.uid ?? 'anonymous';
      final memories = await _localDbService.getMemoriesByUserId(userId);

      setState(() {
        _memories = memories;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showError('Failed to load memories: ${e.toString()}');
    }
  }

  Future<void> _addMemory() async {
    final content = _memoryController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _isAddingMemory = true;
    });

    try {
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

      final success = await _localDbService.saveMemory(memory);

      if (success) {
        _memoryController.clear();
        _showSuccess('Memory added successfully!');
        _loadMemories();
      } else {
        _showError('Failed to add memory');
      }
    } catch (e) {
      _showError('Failed to add memory: ${e.toString()}');
    } finally {
      setState(() {
        _isAddingMemory = false;
      });
    }
  }

  Future<void> _deleteMemory(Memory memory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Memory'),
        content: const Text('Are you sure you want to delete this memory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final success = await _localDbService.deleteMemory(memory.id);
        if (success) {
          _showSuccess('Memory deleted');
          _loadMemories();
        } else {
          _showError('Failed to delete memory');
        }
      } catch (e) {
        _showError('Failed to delete memory: ${e.toString()}');
      }
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _regenerateEmbeddings() async {
    final authService = context.read<AuthService>();
    final userId = authService.currentUser?.uid ?? 'anonymous';

    // Get memories without embeddings
    final memoriesWithoutEmbeddings = await _localDbService.getMemoriesWithoutEmbeddings(userId);

    if (memoriesWithoutEmbeddings.isEmpty) {
      _showSuccess('All memories already have embeddings!');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    int updated = 0;
    for (var memory in memoriesWithoutEmbeddings) {
      try {
        final embedding = await _embeddingService.generateEmbedding(memory.content, isQuery: false);
        await _localDbService.updateMemoryEmbedding(memory.id, embedding);
        updated++;
        print('Updated embedding for memory ${memory.id} ($updated/${memoriesWithoutEmbeddings.length})');
      } catch (e) {
        print('Error generating embedding for memory ${memory.id}: $e');
      }
    }

    setState(() {
      _isLoading = false;
    });

    _showSuccess('Generated embeddings for $updated memories!');
    _loadMemories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Memories'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_fix_high),
            onPressed: _regenerateEmbeddings,
            tooltip: 'Generate Embeddings',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMemories,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Add Memory Section
          Card(
            margin: const EdgeInsets.all(16.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add New Memory',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _memoryController,
                          decoration: const InputDecoration(
                            hintText: 'Type your memory here...',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addMemory(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _isAddingMemory
                          ? const SizedBox(
                              width: 48,
                              height: 48,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              onPressed: _addMemory,
                              icon: const Icon(Icons.add_circle),
                              iconSize: 48,
                              color: Theme.of(context).colorScheme.primary,
                              tooltip: 'Add Memory',
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Memories Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  'Your Memories (${_memories.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (_memories.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete All Memories'),
                          content: const Text('Are you sure you want to delete all memories? This cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                              child: const Text('Delete All'),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        final authService = context.read<AuthService>();
                        final userId = authService.currentUser?.uid ?? 'anonymous';
                        await _localDbService.deleteAllMemoriesForUser(userId);
                        _loadMemories();
                        _showSuccess('All memories deleted');
                      }
                    },
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Clear All'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
          ),

          const Divider(),

          // Memories List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _memories.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.memory,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No memories yet',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add your first memory above or use voice interaction',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[500],
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8.0),
                        itemCount: _memories.length,
                        itemBuilder: (context, index) {
                          final memory = _memories[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 4.0,
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.lightbulb_outline,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              title: Text(
                                memory.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                _formatDate(memory.createdAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteMemory(memory),
                                color: Colors.red[400],
                              ),
                              onTap: () {
                                // Show full memory in a dialog
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Memory'),
                                    content: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(memory.content),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Added: ${_formatDate(memory.createdAt)}',
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Close'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
