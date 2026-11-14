import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../utils/constants.dart';

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
    _controller.addListener(() {
      setState(() => _hasText = _controller.text.trim().isNotEmpty);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send(JarvisService jarvis) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    jarvis.sendTextMessage(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final jarvis    = context.watch<JarvisService>();
    final isListening = jarvis.state == JarvisState.listening;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        border: Border(top: BorderSide(color: JarvisColors.border)),
      ),
      child: Row(
        children: [
          // Mic button
          GestureDetector(
            onTap: () {
              if (isListening) {
                jarvis.stopListening();
              } else {
                jarvis.activateListening();
              }
            },
            child: AnimatedContainer(
              duration: JarvisDurations.fast,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isListening ? JarvisColors.green.withOpacity(0.15) : Colors.transparent,
                border: Border.all(
                  color: isListening ? JarvisColors.green : JarvisColors.cyanDim,
                  width: 1.5,
                ),
                boxShadow: isListening
                    ? [BoxShadow(color: JarvisColors.green.withOpacity(0.4), blurRadius: 12)]
                    : null,
              ),
              child: Icon(
                isListening ? Icons.mic : Icons.mic_none,
                color: isListening ? JarvisColors.green : JarvisColors.cyanDim,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Text input
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _send(jarvis),
                textInputAction: TextInputAction.send,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Send button
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
                    ? [BoxShadow(color: JarvisColors.cyan.withOpacity(0.3), blurRadius: 10)]
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
