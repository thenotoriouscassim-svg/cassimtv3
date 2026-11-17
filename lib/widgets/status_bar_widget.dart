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
      padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
      decoration: BoxDecoration(
        color: JarvisColors.background,
        border: Border(bottom: BorderSide(color: JarvisColors.border.withOpacity(.7))),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: JarvisColors.cyan.withOpacity(.10),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: JarvisColors.cyan.withOpacity(.24)),
              ),
              child: const Icon(Icons.blur_on_rounded, color: JarvisColors.cyan, size: 23),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('JARVIS', style: TextStyle(color: JarvisColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2.2)),
                  SizedBox(height: 2),
                  Text('PERSONAL AI  •  CASSIMTV', style: TextStyle(color: JarvisColors.textDim, fontSize: 8, letterSpacing: 1.35, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Choose assistant model',
              onSelected: jarvis.setSelectedModel,
              color: JarvisColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: JarvisColors.border)),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'auto', child: Text('AUTO  ·  Fastest available')),
                PopupMenuItem(value: 'v1', child: Text('JARVIS v1  ·  Groq')),
                PopupMenuItem(value: 'v2', child: Text('JARVIS v2  ·  NVIDIA')),
                PopupMenuItem(value: 'v3', child: Text('JARVIS v3  ·  Gemini')),
                PopupMenuItem(value: 'v4', child: Text('JARVIS v4  ·  OpenRouter')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: JarvisColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: JarvisColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.tune_rounded, size: 15, color: JarvisColors.cyan),
                  const SizedBox(width: 7),
                  Text(jarvis.selectedModelLabel, style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .6)),
                  const SizedBox(width: 3),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: JarvisColors.textSecondary),
                ]),
              ),
            ),
            const SizedBox(width: 5),
            IconButton(
              tooltip: 'Chat history',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showChats(context, jarvis),
              icon: const Icon(Icons.history_rounded, color: JarvisColors.textSecondary, size: 21),
            ),
            IconButton(
              tooltip: 'JARVIS memory',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showMemory(context),
              icon: const Icon(Icons.psychology_alt_outlined, color: JarvisColors.textSecondary, size: 21),
            ),
            const SizedBox(width: 5),
            InkWell(
              onTap: jarvis.isConnected ? null : jarvis.retryConnection,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: (jarvis.isConnected ? JarvisColors.green : JarvisColors.red).withOpacity(.09),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: (jarvis.isConnected ? JarvisColors.green : JarvisColors.red).withOpacity(.28)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: jarvis.isConnected ? JarvisColors.green : JarvisColors.red)),
                  const SizedBox(width: 6),
                  Text(jarvis.isConnected ? 'ONLINE' : 'RETRY', style: TextStyle(color: jarvis.isConnected ? JarvisColors.green : JarvisColors.red, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: .8)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
