import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../services/memory_service.dart';
import '../utils/constants.dart';

class StatusBarWidget extends StatelessWidget {
  const StatusBarWidget({super.key});

  void _showChats(BuildContext context, JarvisService jarvis) {
    showModalBottomSheet(context: context, backgroundColor: JarvisColors.surface, isScrollControlled: true, builder: (sheetContext) => SafeArea(
      child: SizedBox(height: MediaQuery.of(sheetContext).size.height * .72, child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [const Expanded(child: Text('YOUR CHATS', style: TextStyle(color: JarvisColors.cyan, fontFamily: 'Orbitron', letterSpacing: 2))), IconButton(onPressed: () async { await jarvis.createNewChat(); if (sheetContext.mounted) Navigator.pop(sheetContext); }, icon: const Icon(Icons.add, color: JarvisColors.cyan), tooltip: 'New chat')])),
        const Divider(height: 1),
        Expanded(child: ListView(children: jarvis.savedChats.map((chat) => ListTile(leading: const Icon(Icons.chat_bubble_outline, color: JarvisColors.cyan), title: Text(chat['title']?.toString() ?? 'Chat', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JarvisColors.textPrimary)), selected: chat['id'] == jarvis.activeChatId, onTap: () async { await jarvis.openChat(chat['id'].toString()); if (sheetContext.mounted) Navigator.pop(sheetContext); }, trailing: IconButton(icon: const Icon(Icons.delete_outline, color: JarvisColors.textDim), onPressed: () => jarvis.deleteChat(chat['id'].toString())))).toList())),
      ])),
    ));
  }

  void _showMemory(BuildContext context) {
    final memory = context.read<MemoryService>();
    final keyController = TextEditingController();
    final valueController = TextEditingController();
    showDialog(context: context, builder: (dialogContext) => AlertDialog(
      backgroundColor: JarvisColors.surface,
      title: const Text('JARVIS MEMORY', style: TextStyle(color: JarvisColors.cyan, fontFamily: 'Orbitron', fontSize: 15)),
      content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: keyController, style: const TextStyle(color: JarvisColors.textPrimary), decoration: const InputDecoration(labelText: 'What should JARVIS remember?', labelStyle: TextStyle(color: JarvisColors.textSecondary))),
        TextField(controller: valueController, style: const TextStyle(color: JarvisColors.textPrimary), decoration: const InputDecoration(labelText: 'Details', labelStyle: TextStyle(color: JarvisColors.textSecondary))),
        const SizedBox(height: 12),
        ListenableBuilder(listenable: memory, builder: (_, __) => Column(children: memory.longTermMemory.asMap().entries.map((entry) => ListTile(dense: true, title: Text(entry.value['key'] ?? '', style: const TextStyle(color: JarvisColors.textPrimary)), subtitle: Text(entry.value['value'] ?? '', style: const TextStyle(color: JarvisColors.textSecondary)), trailing: IconButton(icon: const Icon(Icons.close, color: JarvisColors.textDim), onPressed: () => memory.deleteMemory(entry.key)))).toList())),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CLOSE')), TextButton(onPressed: () async { if (keyController.text.trim().isNotEmpty && valueController.text.trim().isNotEmpty) await memory.saveMemory(keyController.text.trim(), valueController.text.trim()); if (dialogContext.mounted) Navigator.pop(dialogContext); }, child: const Text('SAVE MEMORY'))],
    )).then((_) { keyController.dispose(); valueController.dispose(); });
  }

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        border: Border(bottom: BorderSide(color: JarvisColors.border)),
      ),
      child: Row(
        children: [
          // Brand
          RichText(
            text: TextSpan(
              children: [
                TextSpan(text: 'JARVIS AI ', style: TextStyle(
                  color: JarvisColors.cyan, fontSize: 11,
                  fontWeight: FontWeight.bold, letterSpacing: 3,
                  fontFamily: 'Orbitron',
                  shadows: [Shadow(color: JarvisColors.cyan.withOpacity(0.6), blurRadius: 8)],
                )),
                const TextSpan(text: 'by CassimTV', style: TextStyle(
                  color: JarvisColors.textSecondary, fontSize: 8,
                  letterSpacing: 2, fontFamily: 'Orbitron',
                )),
              ],
            ),
          ),

          const Spacer(),
          PopupMenuButton<String>(
            tooltip: 'Choose JARVIS model',
            onSelected: jarvis.setSelectedModel,
            color: JarvisColors.surfaceLight,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'auto', child: Text('AUTO — Fastest successful model')),
              PopupMenuItem(value: 'v1', child: Text('JARVIS v1 — Groq')),
              PopupMenuItem(value: 'v2', child: Text('JARVIS v2 — NVIDIA')),
              PopupMenuItem(value: 'v3', child: Text('JARVIS v3 — Gemini')),
              PopupMenuItem(value: 'v4', child: Text('JARVIS v4 — OpenRouter')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: JarvisColors.cyan.withOpacity(0.7)),
                borderRadius: BorderRadius.circular(4),
                color: JarvisColors.cyan.withOpacity(0.08),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune, color: JarvisColors.cyan, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    jarvis.selectedModelLabel,
                    style: const TextStyle(
                      color: JarvisColors.cyan,
                      fontSize: 9,
                      letterSpacing: 1,
                      fontFamily: 'Orbitron',
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down, color: JarvisColors.cyan, size: 14),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(tooltip: 'Chat history', onPressed: () => _showChats(context, jarvis), icon: const Icon(Icons.history, color: JarvisColors.cyan, size: 20)),
          IconButton(tooltip: 'JARVIS memory', onPressed: () => _showMemory(context), icon: const Icon(Icons.psychology_alt_outlined, color: JarvisColors.cyan, size: 20)),

          // Connection indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(
                color: jarvis.isConnected ? JarvisColors.green : JarvisColors.red,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 4, height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: jarvis.isConnected ? JarvisColors.green : JarvisColors.red,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  jarvis.isConnected ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    color: jarvis.isConnected ? JarvisColors.green : JarvisColors.red,
                    fontSize: 8, letterSpacing: 1, fontFamily: 'Orbitron',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Retry connection
          if (!jarvis.isConnected)
            GestureDetector(
              onTap: jarvis.retryConnection,
              child: const Icon(Icons.refresh, color: JarvisColors.textSecondary, size: 16),
            ),
        ],
      ),
    );
  }
}
