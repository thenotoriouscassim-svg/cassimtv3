import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../services/memory_service.dart';
import '../utils/constants.dart';
import '../screens/call_screen.dart';

class InputBar extends StatefulWidget {
  const InputBar({super.key});

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    final value = _controller.text.trim().isNotEmpty;
    if (mounted && value != _hasText) setState(() => _hasText = value);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _send(JarvisService jarvis) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    jarvis.sendTextMessage(text, memoryContext: context.read<MemoryService>().buildMemoryContext());
    _controller.clear();
  }

  void _search(JarvisService jarvis) {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    jarvis.searchWeb(query);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF121C25),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _hasText ? JarvisColors.cyan.withOpacity(.45) : JarvisColors.border),
                    boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 22, offset: Offset(0, 7))],
                  ),
                  child: Row(children: [
                    const SizedBox(width: 17),
                    const Icon(Icons.add_rounded, color: JarvisColors.textDim, size: 21),
                    const SizedBox(width: 9),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(jarvis),
                        style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 14, height: 1.5),
                        decoration: InputDecoration(
                          hintText: jarvis.isConnected ? 'Message JARVIS' : 'Connecting to JARVIS…',
                          hintStyle: const TextStyle(color: JarvisColors.textDim, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 17),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Search the web',
                      onPressed: _hasText ? () => _search(jarvis) : null,
                      icon: Icon(Icons.travel_explore_rounded, color: _hasText ? JarvisColors.cyan : JarvisColors.textDim, size: 20),
                    ),
                    const SizedBox(width: 5),
                  ]),
                ),
              ),
              const SizedBox(width: 9),
              _RoundAction(icon: Icons.mic_none_rounded, tooltip: 'Call JARVIS', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen()))),
              const SizedBox(width: 8),
              _RoundAction(icon: Icons.arrow_upward_rounded, tooltip: 'Send', active: _hasText, onTap: _hasText ? () => _send(jarvis) : null),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  const _RoundAction({required this.icon, required this.tooltip, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? JarvisColors.cyan : JarvisColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: active ? JarvisColors.cyan : JarvisColors.border)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 50,
            height: 52,
            child: Icon(icon, color: active ? JarvisColors.background : JarvisColors.textSecondary, size: 21),
          ),
        ),
      ),
    );
  }
}
