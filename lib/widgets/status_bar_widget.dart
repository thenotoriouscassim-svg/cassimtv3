import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../services/memory_service.dart';
import '../utils/constants.dart';

class StatusBarWidget extends StatelessWidget {
  const StatusBarWidget({super.key});

  void _showChats(BuildContext context, JarvisService jarvis) {
    showModalBottomSheet(
      context: context,
      backgroundColor: JarvisColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .72,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
              child: Row(children: [
                const Expanded(child: Text('Chat history', style: TextStyle(color: JarvisColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700))),
                TextButton.icon(
                  onPressed: () async {
                    await jarvis.createNewChat();
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New chat'),
                ),
              ]),
            ),
            const Divider(height: 1, color: JarvisColors.border),
            Expanded(
              child: ListView.builder(
                itemCount: jarvis.savedChats.length,
                itemBuilder: (context, index) {
                  final chat = jarvis.savedChats[index];
                  return ListTile(
                    leading: const Icon(Icons.chat_bubble_outline, color: JarvisColors.textSecondary),
                    title: Text(chat['title']?.toString() ?? 'Chat', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: JarvisColors.textPrimary)),
                    selected: chat['id'] == jarvis.activeChatId,
                    onTap: () async {
                      await jarvis.openChat(chat['id'].toString());
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: JarvisColors.textDim),
                      onPressed: () => jarvis.deleteChat(chat['id'].toString()),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showMemory(BuildContext context) {
    final memory = context.read<MemoryService>();
    final keyController = TextEditingController();
    final valueController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: JarvisColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('JARVIS memory', style: TextStyle(color: JarvisColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: keyController, style: const TextStyle(color: JarvisColors.textPrimary), decoration: const InputDecoration(labelText: 'Memory title')),
              TextField(controller: valueController, style: const TextStyle(color: JarvisColors.textPrimary), decoration: const InputDecoration(labelText: 'Details')),
              const SizedBox(height: 12),
              ListenableBuilder(
                listenable: memory,
                builder: (_, __) => Column(children: memory.longTermMemory.asMap().entries.map((entry) => ListTile(
                  dense: true,
                  title: Text(entry.value['key'] ?? '', style: const TextStyle(color: JarvisColors.textPrimary)),
                  subtitle: Text(entry.value['value'] ?? '', style: const TextStyle(color: JarvisColors.textSecondary)),
                  trailing: IconButton(icon: const Icon(Icons.close, color: JarvisColors.textDim), onPressed: () => memory.deleteMemory(entry.key)),
                )).toList()),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              if (keyController.text.trim().isNotEmpty && valueController.text.trim().isNotEmpty) {
                await memory.saveMemory(keyController.text.trim(), valueController.text.trim());
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save memory'),
          ),
        ],
      ),
    ).then((_) {
      keyController.dispose();
      valueController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    return SafeArea(
      bottom: false,
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: const BoxDecoration(
          color: Color(0xD90B1118),
          border: Border(bottom: BorderSide(color: JarvisColors.border, width: .7)),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF172B31),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JarvisColors.cyan.withOpacity(.24)),
            ),
            child: const Center(child: Text('J', style: TextStyle(color: JarvisColors.cyan, fontSize: 21, fontWeight: FontWeight.w800))),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('JARVIS', style: TextStyle(color: JarvisColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2)),
                SizedBox(height: 2),
                Text('PERSONAL ASSISTANT', style: TextStyle(color: JarvisColors.textDim, fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Choose model',
            onSelected: jarvis.setSelectedModel,
            color: JarvisColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: JarvisColors.border)),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'auto', child: Text('AUTO')),
              PopupMenuItem(value: 'v1', child: Text('JARVIS v1')),
              PopupMenuItem(value: 'v2', child: Text('JARVIS v2')),
              PopupMenuItem(value: 'v3', child: Text('JARVIS v3')),
              PopupMenuItem(value: 'v4', child: Text('JARVIS v4')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: JarvisColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: JarvisColors.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.tune_rounded, size: 15, color: JarvisColors.cyan),
                const SizedBox(width: 7),
                Text(jarvis.selectedModelLabel, style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
                const Icon(Icons.keyboard_arrow_down, size: 16, color: JarvisColors.textSecondary),
              ]),
            ),
          ),
          const SizedBox(width: 5),
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'history') _showChats(context, jarvis);
              if (value == 'memory') _showMemory(context);
            },
            color: JarvisColors.surface,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history_rounded), title: Text('Chat history'), contentPadding: EdgeInsets.zero)),
              PopupMenuItem(value: 'memory', child: ListTile(leading: Icon(Icons.psychology_alt_outlined), title: Text('Memory'), contentPadding: EdgeInsets.zero)),
            ],
            icon: const Icon(Icons.more_horiz_rounded, color: JarvisColors.textSecondary),
          ),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: (jarvis.isConnected ? JarvisColors.green : JarvisColors.red).withOpacity(.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: (jarvis.isConnected ? JarvisColors.green : JarvisColors.red).withOpacity(.22)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: jarvis.isConnected ? JarvisColors.green : JarvisColors.red)),
              const SizedBox(width: 6),
              Text(jarvis.isConnected ? 'ONLINE' : 'OFFLINE', style: TextStyle(color: jarvis.isConnected ? JarvisColors.green : JarvisColors.red, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .5)),
            ]),
          ),
        ]),
      ),
    );
  }
}
