import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/memory_service.dart';
import '../utils/constants.dart';

class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final memory = context.watch<MemoryService>();
    final items  = memory.longTermMemory;

    return Scaffold(
      backgroundColor: JarvisColors.background,
      appBar: AppBar(
        backgroundColor: JarvisColors.surface,
        title: const Text('JARVIS MEMORY', style: TextStyle(
          color: JarvisColors.cyan, fontSize: 14, letterSpacing: 4, fontFamily: 'Orbitron')),
        iconTheme: const IconThemeData(color: JarvisColors.cyan),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClear(context, memory),
              child: const Text('CLEAR ALL', style: TextStyle(
                color: JarvisColors.red, fontSize: 10, fontFamily: 'Orbitron')),
            ),
        ],
        elevation: 0,
      ),
      body: items.isEmpty
          ? Center(
              child: Text('No memories stored yet, sir.',
                style: const TextStyle(color: JarvisColors.textDim,
                  fontSize: 12, fontFamily: 'Orbitron')),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: JarvisColors.surfaceLight,
                    border: Border.all(color: JarvisColors.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['key'] ?? '', style: const TextStyle(
                              color: JarvisColors.cyan, fontSize: 10,
                              letterSpacing: 1, fontFamily: 'Orbitron')),
                            const SizedBox(height: 4),
                            Text(item['value'] ?? '', style: const TextStyle(
                              color: JarvisColors.textPrimary, fontSize: 12,
                              fontFamily: 'Orbitron', height: 1.4)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => memory.deleteMemory(i),
                        icon: const Icon(Icons.delete_outline, color: JarvisColors.red, size: 18),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _confirmClear(BuildContext context, MemoryService memory) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: JarvisColors.surfaceLight,
        title: const Text('CLEAR ALL MEMORY', style: TextStyle(
          color: JarvisColors.red, fontSize: 13, fontFamily: 'Orbitron')),
        content: const Text('This will permanently delete all stored memories. Are you sure, sir?',
          style: TextStyle(color: JarvisColors.textPrimary, fontSize: 11, fontFamily: 'Orbitron')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL', style: TextStyle(color: JarvisColors.textSecondary, fontFamily: 'Orbitron')),
          ),
          TextButton(
            onPressed: () { memory.clearAllMemory(); Navigator.pop(context); },
            child: const Text('CONFIRM', style: TextStyle(color: JarvisColors.red, fontFamily: 'Orbitron')),
          ),
        ],
      ),
    );
  }
}
