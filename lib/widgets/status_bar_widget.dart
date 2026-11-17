import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../services/memory_service.dart';

// ─────────────────────────────────────────────
// Colour tokens
// ─────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF050508);
  static const surface = Color(0xFF0D0D18);
  static const surface2 = Color(0xFF111827);
  static const border = Color(0xFF1E2D3D);
  static const cyan = Color(0xFF00C8FF);
  static const purple = Color(0xFF7B2FFF);
  static const red = Color(0xFFFF3B5C);
  static const green = Color(0xFF00E5A0);
  static const textHi = Color(0xFFE8F4FF);
  static const textMid = Color(0xFF7A9AB8);
  static const textDim = Color(0xFF3A5068);
}

class StatusBarWidget extends StatelessWidget {
  const StatusBarWidget({super.key});

  void _showChats(BuildContext context, JarvisService jarvis) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ChatHistorySheet(jarvis: jarvis),
    );
  }

  void _showMemory(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _MemoryDialog(memory: context.read<MemoryService>()),
    );
  }

  void _openDrawer(BuildContext context, JarvisService jarvis) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _HamburgerDrawer(
        jarvis: jarvis,
        onShowChats: () {
          Navigator.pop(sheetContext);
          Future.delayed(const Duration(milliseconds: 180), () {
            if (context.mounted) _showChats(context, jarvis);
          });
        },
        onShowMemory: () {
          Navigator.pop(sheetContext);
          Future.delayed(const Duration(milliseconds: 180), () {
            if (context.mounted) _showMemory(context);
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();

    return SafeArea(
      bottom: false,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _C.bg.withOpacity(0.96),
          border: const Border(bottom: BorderSide(color: _C.border, width: 1)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _C.surface,
                border: Border.all(color: _C.cyan.withOpacity(0.4), width: 1.5),
                boxShadow: [BoxShadow(color: _C.cyan.withOpacity(0.15), blurRadius: 12)],
              ),
              child: const Center(
                child: Text('J', style: TextStyle(
                  color: _C.cyan, fontFamily: 'Exo 2', fontSize: 18,
                  fontWeight: FontWeight.w800, height: 1,
                )),
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('JARVIS', style: TextStyle(
                  color: _C.textHi, fontFamily: 'Exo 2', fontSize: 14,
                  fontWeight: FontWeight.w800, letterSpacing: 3,
                )),
                SizedBox(height: 2),
                Text('PERSONAL AI', style: TextStyle(
                  color: _C.textDim, fontFamily: 'Exo 2', fontSize: 8,
                  letterSpacing: 2.5, fontWeight: FontWeight.w600,
                )),
              ],
            ),
            const Spacer(),
            if (jarvis.developerMode) ...[
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(color: _C.purple.withOpacity(0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: _C.purple.withOpacity(0.4))), child: const Text('DEVELOPER', style: TextStyle(color: _C.purple, fontFamily: 'Exo 2', fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1))),
              const SizedBox(width: 8),
            ],
            _ModelPill(jarvis: jarvis),
            const SizedBox(width: 8),
            _StatusDot(connected: jarvis.isConnected),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _openDrawer(context, jarvis),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _C.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _C.border),
                ),
                child: const Icon(Icons.menu_rounded, color: _C.textMid, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelPill extends StatelessWidget {
  final JarvisService jarvis;
  const _ModelPill({required this.jarvis});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Choose model',
      onSelected: jarvis.setSelectedModel,
      color: _C.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _C.border),
      ),
      offset: const Offset(0, 44),
      itemBuilder: (_) => [
        _modelItem('auto', 'Auto'),
        _modelItem('v1', 'JARVIS v1'),
        _modelItem('v2', 'JARVIS v2'),
        _modelItem('v3', 'JARVIS v3'),
        _modelItem('v4', 'JARVIS v4'),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _C.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune_rounded, size: 13, color: _C.cyan),
            const SizedBox(width: 6),
            Text(jarvis.selectedModelLabel, style: const TextStyle(
              color: _C.textHi, fontFamily: 'Exo 2', fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 0.3,
            )),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: _C.textDim),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _modelItem(String value, String label) => PopupMenuItem(
    value: value,
    child: Text(label, style: const TextStyle(
      color: _C.textHi, fontFamily: 'Exo 2', fontSize: 13,
      fontWeight: FontWeight.w500,
    )),
  );
}

class _StatusDot extends StatelessWidget {
  final bool connected;
  const _StatusDot({required this.connected});

  @override
  Widget build(BuildContext context) {
    final color = connected ? _C.green : _C.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 5),
          Text(connected ? 'ONLINE' : 'OFFLINE', style: TextStyle(
            color: color, fontFamily: 'Exo 2', fontSize: 9,
            fontWeight: FontWeight.w700, letterSpacing: 1,
          )),
        ],
      ),
    );
  }
}

class _HamburgerDrawer extends StatelessWidget {
  final JarvisService jarvis;
  final VoidCallback onShowChats;
  final VoidCallback onShowMemory;

  const _HamburgerDrawer({
    required this.jarvis,
    required this.onShowChats,
    required this.onShowMemory,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _C.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _C.bg,
                      border: Border.all(color: _C.cyan.withOpacity(0.35), width: 1.5),
                      boxShadow: [BoxShadow(color: _C.cyan.withOpacity(0.12), blurRadius: 14)],
                    ),
                    child: const Center(child: Text('J', style: TextStyle(
                      color: _C.cyan, fontFamily: 'Exo 2', fontSize: 20,
                      fontWeight: FontWeight.w800, height: 1,
                    ))),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('JARVIS', style: TextStyle(
                        color: _C.textHi, fontFamily: 'Exo 2', fontSize: 16,
                        fontWeight: FontWeight.w800, letterSpacing: 3,
                      )),
                      SizedBox(height: 2),
                      Text('CassimTV Personal AI', style: TextStyle(
                        color: _C.textDim, fontFamily: 'Exo 2', fontSize: 11,
                        fontWeight: FontWeight.w500,
                      )),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close_rounded, color: _C.textDim, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _C.border),
            const SizedBox(height: 8),
            _DrawerTile(
              icon: Icons.add_circle_outline_rounded,
              label: 'New chat',
              color: _C.cyan,
              onTap: () async {
                Navigator.pop(context);
                await jarvis.createNewChat();
              },
            ),
            _DrawerTile(
              icon: Icons.history_rounded,
              label: 'Chat history',
              color: _C.textMid,
              onTap: onShowChats,
            ),
            _DrawerTile(
              icon: Icons.psychology_alt_outlined,
              label: 'Memory',
              color: _C.textMid,
              onTap: onShowMemory,
            ),
            const Divider(height: 1, color: _C.border),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  const Text('Model', style: TextStyle(
                    color: _C.textDim, fontFamily: 'Exo 2', fontSize: 11,
                    fontWeight: FontWeight.w600, letterSpacing: 1,
                  )),
                  const Spacer(),
                  _ModelPill(jarvis: jarvis),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Connection', style: TextStyle(
                    color: _C.textDim, fontFamily: 'Exo 2', fontSize: 11,
                    fontWeight: FontWeight.w600, letterSpacing: 1,
                  )),
                  const Spacer(),
                  _StatusDot(connected: jarvis.isConnected),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 4, height: 4, decoration: const BoxDecoration(shape: BoxShape.circle, color: _C.cyan)),
                  const SizedBox(width: 8),
                  const Text('JARVIS  ·  CASSIMTV', style: TextStyle(
                    color: _C.textDim, fontFamily: 'Exo 2', fontSize: 9,
                    letterSpacing: 2.5, fontWeight: FontWeight.w600,
                  )),
                  const SizedBox(width: 8),
                  Container(width: 4, height: 4, decoration: const BoxDecoration(shape: BoxShape.circle, color: _C.cyan)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_DrawerTile> createState() => _DrawerTileState();
}

class _DrawerTileState extends State<_DrawerTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: _pressed ? _C.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _pressed ? _C.border : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(widget.icon, color: widget.color, size: 18),
            const SizedBox(width: 14),
            Text(widget.label, style: TextStyle(
              color: widget.color == _C.textMid ? _C.textHi : widget.color,
              fontFamily: 'Exo 2', fontSize: 14, fontWeight: FontWeight.w500,
            )),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: _C.textDim, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ChatHistorySheet extends StatelessWidget {
  final JarvisService jarvis;
  const _ChatHistorySheet({required this.jarvis});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        height: MediaQuery.of(context).size.height * 0.68,
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _C.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40)],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              child: Row(
                children: [
                  const Text('Chat history', style: TextStyle(
                    color: _C.textHi, fontFamily: 'Exo 2', fontSize: 17,
                    fontWeight: FontWeight.w700,
                  )),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await jarvis.createNewChat();
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _C.cyan.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _C.cyan.withOpacity(0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 14, color: _C.cyan),
                          SizedBox(width: 5),
                          Text('New chat', style: TextStyle(
                            color: _C.cyan, fontFamily: 'Exo 2', fontSize: 12,
                            fontWeight: FontWeight.w700,
                          )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _C.border),
            Expanded(
              child: ListenableBuilder(
                listenable: jarvis,
                builder: (context, _) {
                  final chats = jarvis.savedChats;
                  if (chats.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_outline_rounded, color: _C.textDim, size: 32),
                          const SizedBox(height: 10),
                          const Text('No saved chats', style: TextStyle(
                            color: _C.textDim, fontFamily: 'Exo 2', fontSize: 13,
                          )),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: chats.length,
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      final isActive = chat['id'] == jarvis.activeChatId;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive ? _C.cyan.withOpacity(0.07) : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isActive ? _C.cyan.withOpacity(0.25) : Colors.transparent,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                          leading: Icon(Icons.chat_bubble_outline_rounded, color: isActive ? _C.cyan : _C.textDim, size: 18),
                          title: Text(chat['title']?.toString() ?? 'Chat',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive ? _C.textHi : _C.textMid,
                              fontFamily: 'Exo 2', fontSize: 13,
                              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, size: 16),
                            color: _C.textDim,
                            onPressed: () => jarvis.deleteChat(chat['id'].toString()),
                          ),
                          onTap: () async {
                            await jarvis.openChat(chat['id'].toString());
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryDialog extends StatefulWidget {
  final MemoryService memory;
  const _MemoryDialog({required this.memory});

  @override
  State<_MemoryDialog> createState() => _MemoryDialogState();
}

class _MemoryDialogState extends State<_MemoryDialog> {
  final _keyCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  InputDecoration _inputDecor(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _C.textDim, fontFamily: 'Exo 2', fontSize: 12),
    filled: true,
    fillColor: _C.bg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _C.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: _C.cyan.withOpacity(0.5), width: 1.5),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _C.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _C.purple.withOpacity(0.12),
                      border: Border.all(color: _C.purple.withOpacity(0.35)),
                    ),
                    child: const Icon(Icons.psychology_alt_outlined, color: _C.purple, size: 16),
                  ),
                  const SizedBox(width: 12),
                  const Text('Memory', style: TextStyle(
                    color: _C.textHi, fontFamily: 'Exo 2', fontSize: 17,
                    fontWeight: FontWeight.w700,
                  )),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close_rounded, color: _C.textDim, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _C.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _keyCtrl,
                      style: const TextStyle(color: _C.textHi, fontFamily: 'Exo 2', fontSize: 13),
                      decoration: _inputDecor('Memory title'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _valueCtrl,
                      style: const TextStyle(color: _C.textHi, fontFamily: 'Exo 2', fontSize: 13),
                      decoration: _inputDecor('Details'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () async {
                        final key = _keyCtrl.text.trim();
                        final value = _valueCtrl.text.trim();
                        if (key.isEmpty || value.isEmpty) return;
                        await widget.memory.saveMemory(key, value);
                        if (!mounted) return;
                        _keyCtrl.clear();
                        _valueCtrl.clear();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _C.cyan.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _C.cyan.withOpacity(0.3)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.save_outlined, color: _C.cyan, size: 15),
                            SizedBox(width: 8),
                            Text('Save to memory', style: TextStyle(
                              color: _C.cyan, fontFamily: 'Exo 2', fontSize: 13,
                              fontWeight: FontWeight.w700,
                            )),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ListenableBuilder(
                      listenable: widget.memory,
                      builder: (_, __) {
                        final items = widget.memory.longTermMemory;
                        if (items.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: Text('No memories saved yet', style: TextStyle(
                              color: _C.textDim, fontFamily: 'Exo 2', fontSize: 12,
                            ))),
                          );
                        }
                        return Column(
                          children: items.asMap().entries.map((entry) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                            decoration: BoxDecoration(
                              color: _C.bg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _C.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(entry.value['key'] ?? '', style: const TextStyle(
                                        color: _C.textHi, fontFamily: 'Exo 2', fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      )),
                                      const SizedBox(height: 3),
                                      Text(entry.value['value'] ?? '', style: const TextStyle(
                                        color: _C.textMid, fontFamily: 'Exo 2', fontSize: 11,
                                      )),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => widget.memory.deleteMemory(entry.key),
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(Icons.delete_outline_rounded, color: _C.textDim, size: 16),
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
