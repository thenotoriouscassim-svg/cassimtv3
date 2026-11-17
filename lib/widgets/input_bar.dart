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
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    if (!mounted) return;
    final value = _controller.text.trim().isNotEmpty;
    if (value != _hasText) setState(() => _hasText = value);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
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

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        color: JarvisColors.background,
        border: Border(top: BorderSide(color: JarvisColors.border.withOpacity(.7))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: JarvisDurations.fast,
                constraints: const BoxConstraints(minHeight: 54),
                decoration: BoxDecoration(
                  color: JarvisColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _hasText ? JarvisColors.cyan.withOpacity(.55) : JarvisColors.border),
                  boxShadow: _hasText ? [BoxShadow(color: JarvisColors.cyan.withOpacity(.07), blurRadius: 18)] : null,
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Icon(Icons.auto_awesome, size: 18, color: _hasText ? JarvisColors.cyan : JarvisColors.textDim),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 14, height: 1.4),
                        decoration: InputDecoration(
                          hintText: jarvis.isConnected ? 'Message JARVIS…' : 'Connecting to JARVIS…',
                          hintStyle: const TextStyle(color: JarvisColors.textDim, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        onSubmitted: (_) => _send(jarvis),
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Search the web',
                      visualDensity: VisualDensity.compact,
                      onPressed: _hasText ? () {
                        final query = _controller.text.trim();
                        FocusScope.of(context).unfocus();
                        jarvis.searchWeb(query);
                        _controller.clear();
                      } : null,
                      icon: Icon(Icons.travel_explore_rounded, size: 19, color: _hasText ? JarvisColors.cyan : JarvisColors.textDim),
                    ),
                    const SizedBox(width: 5),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 9),
            _ActionButton(
              icon: Icons.mic_none_rounded,
              color: JarvisColors.cyan,
              tooltip: 'Call JARVIS',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen())),
            ),
            const SizedBox(width: 8),
            _ActionButton(
              icon: Icons.arrow_upward_rounded,
              color: Colors.white,
              filled: true,
              enabled: _hasText,
              tooltip: 'Send message',
              onTap: _hasText ? () => _send(jarvis) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;
  final bool filled;
  final bool enabled;
  const _ActionButton({required this.icon, required this.color, required this.tooltip, required this.onTap, this.filled = false, this.enabled = true});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: filled
          ? (enabled ? JarvisColors.cyan : JarvisColors.surfaceLight)
          : JarvisColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: filled ? Colors.transparent : JarvisColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: SizedBox(
          width: 52,
          height: 54,
          child: Icon(icon, color: filled ? (enabled ? JarvisColors.background : JarvisColors.textDim) : color, size: 22),
        ),
      ),
    ),
  );
}