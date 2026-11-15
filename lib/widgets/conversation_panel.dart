import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
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
  bool _wasAtBottom = true;
  int _lastMessageCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final distance = _scroll.position.maxScrollExtent - _scroll.position.pixels;
    _wasAtBottom = distance < 100;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    final msgs = jarvis.conversation;

    if (msgs.length > _lastMessageCount && _wasAtBottom) {
      _scrollToBottom();
    }
    _lastMessageCount = msgs.length;

    return Container(
      color: JarvisColors.background,
      child: msgs.isEmpty
          ? _buildEmpty()
          : NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification ||
                    notification is ScrollEndNotification) {
                  _onScroll();
                }
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: msgs.length,
                itemBuilder: (_, i) => _MessageBubble(message: msgs[i]),
              ),
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, color: JarvisColors.textDim, size: 32),
          const SizedBox(height: 12),
          Text(
            'Ask JARVIS anything',
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

class _MessageBubble extends StatefulWidget {
  final Message message;
  const _MessageBubble({required this.message});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  final List<TapGestureRecognizer> _linkRecognizers = [];

  @override
  void dispose() {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  TextSpan _buildMessageSpan(String content, TextStyle baseStyle) {
    for (final recognizer in _linkRecognizers) {
      recognizer.dispose();
    }
    _linkRecognizers.clear();
    final urlPattern = RegExp(r'https?://[^\s]+');
    final spans = <TextSpan>[];
    var lastIndex = 0;
    for (final match in urlPattern.allMatches(content)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: content.substring(lastIndex, match.start)));
      }
      final url = match.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        };
      _linkRecognizers.add(recognizer);
      spans.add(TextSpan(
        text: url,
        style: const TextStyle(color: JarvisColors.cyan, decoration: TextDecoration.underline),
        recognizer: recognizer,
      ));
      lastIndex = match.end;
    }
    if (lastIndex < content.length) {
      spans.add(TextSpan(text: content.substring(lastIndex)));
    }
    return TextSpan(style: baseStyle, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.role == MessageRole.user;
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
                      topLeft: Radius.circular(isUser ? 12 : 2),
                      topRight: Radius.circular(isUser ? 2 : 12),
                      bottomLeft: const Radius.circular(12),
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
                  child: SelectableText.rich(
                    _buildMessageSpan(
                      message.content,
                      TextStyle(
                        color: message.isError ? JarvisColors.red : JarvisColors.textPrimary,
                        fontSize: 13,
                        height: 1.6,
                        fontFamily: 'Orbitron',
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(
                        color: JarvisColors.textDim,
                        fontSize: 8,
                        fontFamily: 'Orbitron',
                      ),
                    ),
                    if (isAssistant)
                      IconButton(
                        tooltip: 'Copy response',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.copy, size: 14, color: JarvisColors.textSecondary),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: message.content));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Copied to clipboard'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                      ),
                  ],
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
