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
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
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
    jarvis.sendTextMessage(text, memoryContext: context.read<MemoryService>().buildMemoryContext());
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        border: Border(top: BorderSide(color: JarvisColors.border)),
      ),
      child: Row(
        children: [
          // Text input and recognized speech.
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: JarvisColors.surfaceLight,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: JarvisColors.border),
              ),
              child: TextField(
                controller: _controller,
                style: const TextStyle(
                  color: JarvisColors.textPrimary,
                  fontSize: 13,
                  fontFamily: 'Orbitron',
                ),
                decoration: InputDecoration(
                  hintText: jarvis.isConnected
                      ? 'Ask JARVIS anything...'
                      : 'Backend offline — type to queue',
                  hintStyle: TextStyle(
                    color: JarvisColors.textDim,
                    fontSize: 11,
                    fontFamily: 'Orbitron',
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _send(jarvis),
                textInputAction: TextInputAction.send,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Dedicated live web-search tool. This does not alter normal chat.
          IconButton(
            tooltip: 'Search the live web',
            onPressed: _hasText
                ? () {
                    final query = _controller.text.trim();
                    if (query.isEmpty) return;
                    jarvis.searchWeb(query);
                    _controller.clear();
                  }
                : null,
            icon: Icon(
              Icons.travel_explore,
              color: _hasText ? JarvisColors.cyan : JarvisColors.textDim,
              size: 21,
            ),
          ),

          IconButton(
            tooltip: 'Call JARVIS',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallScreen())),
            icon: const Icon(Icons.call, color: JarvisColors.green, size: 22),
          ),
          const SizedBox(width: 4),

          // Send button.
          GestureDetector(
            onTap: _hasText ? () => _send(jarvis) : null,
            child: AnimatedContainer(
              duration: JarvisDurations.fast,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hasText
                    ? JarvisColors.cyan.withOpacity(0.15)
                    : Colors.transparent,
                border: Border.all(
                  color: _hasText ? JarvisColors.cyan : JarvisColors.border,
                  width: 1.5,
                ),
                boxShadow: _hasText
                    ? [
                        BoxShadow(
                          color: JarvisColors.cyan.withOpacity(0.3),
                          blurRadius: 10,
                        )
                      ]
                    : null,
              ),
              child: Icon(
                Icons.send,
                color: _hasText ? JarvisColors.cyan : JarvisColors.textDim,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
