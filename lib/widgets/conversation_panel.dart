import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../models/message.dart';
import '../utils/constants.dart';

class ConversationPanel extends StatefulWidget {
  const ConversationPanel({super.key});
  @override
  State<ConversationPanel> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends State<ConversationPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    final msgs   = jarvis.conversation;

    if (msgs.isNotEmpty) _scrollToBottom();

    return Container(
      color: JarvisColors.background,
      child: msgs.isEmpty
          ? _buildEmpty()
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: msgs.length,
              itemBuilder: (_, i) => _MessageBubble(message: msgs[i]),
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_none, color: JarvisColors.textDim, size: 32),
          const SizedBox(height: 12),
          Text(
            'Say "Jarvis!" to begin',
            style: TextStyle(
              color: JarvisColors.textDim,
              fontSize: 13,
              letterSpacing: 2,
              fontFamily: 'Orbitron',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'or type a message below',
            style: TextStyle(
              color: JarvisColors.textDim.withOpacity(0.6),
              fontSize: 10,
              letterSpacing: 1,
              fontFamily: 'Orbitron',
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser      = message.role == MessageRole.user;
    final isAssistant = message.role == MessageRole.assistant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (isAssistant) ...[
            _Avatar(isJarvis: true),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  isUser ? 'YOU' : 'JARVIS',
                  style: TextStyle(
                    color: isUser ? JarvisColors.electricBlue : JarvisColors.cyan,
                    fontSize: 9,
                    letterSpacing: 2,
                    fontFamily: 'Orbitron',
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser ? JarvisColors.glowBlue : JarvisColors.surfaceLight,
                    borderRadius: BorderRadius.only(
                      topLeft:     Radius.circular(isUser ? 12 : 2),
                      topRight:    Radius.circular(isUser ? 2  : 12),
                      bottomLeft:  const Radius.circular(12),
                      bottomRight: const Radius.circular(12),
                    ),
                    border: Border.all(
                      color: isUser
                          ? JarvisColors.electricBlue.withOpacity(0.3)
                          : message.isError
                              ? JarvisColors.red.withOpacity(0.3)
                              : JarvisColors.cyan.withOpacity(0.2),
                    ),
                    boxShadow: isAssistant
                        ? [BoxShadow(color: JarvisColors.cyan.withOpacity(0.05), blurRadius: 8)]
                        : null,
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: message.isError ? JarvisColors.red : JarvisColors.textPrimary,
                      fontSize: 13,
                      height: 1.6,
                      fontFamily: 'Orbitron',
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    color: JarvisColors.textDim,
                    fontSize: 8,
                    fontFamily: 'Orbitron',
                  ),
                ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 10),
            _Avatar(isJarvis: false),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _Avatar extends StatelessWidget {
  final bool isJarvis;
  const _Avatar({required this.isJarvis});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isJarvis ? JarvisColors.cyan : JarvisColors.electricBlue,
          width: 1,
        ),
        color: JarvisColors.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: (isJarvis ? JarvisColors.cyan : JarvisColors.electricBlue).withOpacity(0.3),
            blurRadius: 6,
          ),
        ],
      ),
      child: Center(
        child: Text(
          isJarvis ? 'J' : 'U',
          style: TextStyle(
            color: isJarvis ? JarvisColors.cyan : JarvisColors.electricBlue,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'Orbitron',
          ),
        ),
      ),
    );
  }
}
