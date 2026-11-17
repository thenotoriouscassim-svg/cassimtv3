import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../services/memory_service.dart';
import '../models/message.dart';
import '../utils/constants.dart';

class ConversationPanel extends StatefulWidget {
  const ConversationPanel({super.key});

  @override
  State<ConversationPanel> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends State<ConversationPanel> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
      }
    });
  }

  void _sendPrompt(BuildContext context, String prompt) {
    final jarvis = context.read<JarvisService>();
    final memory = context.read<MemoryService>();
    jarvis.sendTextMessage(prompt, memoryContext: memory.buildMemoryContext());
  }

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    final messages = jarvis.conversation;
    if (messages.length > _lastCount) _scrollToBottom();
    _lastCount = messages.length;

    if (messages.isEmpty) return _buildWelcome(context);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
      itemCount: messages.length + (jarvis.state == JarvisState.processing ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) return const _ThinkingIndicator();
        return Align(
          alignment: messages[index].role == MessageRole.user ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: _MessageBubble(message: messages[index], animate: jarvis.isTypingResponse && index == messages.length - 1),
          ),
        );
      },
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final suggestions = [
      (Icons.code_rounded, 'Build something', 'Help me build an app'),
      (Icons.travel_explore_rounded, 'Research a topic', 'Research the latest technology news'),
      (Icons.lightbulb_outline_rounded, 'Think it through', 'Help me plan a new project'),
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF172B31),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: JarvisColors.cyan.withOpacity(.2)),
                ),
                child: const Center(child: Text('J', style: TextStyle(color: JarvisColors.cyan, fontSize: 29, fontWeight: FontWeight.w800))),
              ),
              const SizedBox(height: 22),
              const Text('What can I help you with?', textAlign: TextAlign.center, style: TextStyle(color: JarvisColors.textPrimary, fontSize: 27, fontWeight: FontWeight.w700, letterSpacing: -.8)),
              const SizedBox(height: 9),
              const Text('Ask a question, explore an idea, or get something done.', textAlign: TextAlign.center, style: TextStyle(color: JarvisColors.textSecondary, fontSize: 13, height: 1.5)),
              const SizedBox(height: 30),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: suggestions.map((item) => SizedBox(
                  width: 195,
                  child: Material(
                    color: JarvisColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _sendPrompt(context, item.$3),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: JarvisColors.border)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(item.$1, color: JarvisColors.cyan, size: 20),
                          const SizedBox(height: 15),
                          Text(item.$2, style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          const Text('Start a conversation', style: TextStyle(color: JarvisColors.textDim, fontSize: 10)),
                        ]),
                      ),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 26),
              const Text('JARVIS AI  /  CASSIMTV', style: TextStyle(color: JarvisColors.textDim, fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  const _ThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 12, left: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(JarvisColors.cyan))),
        const SizedBox(width: 10),
        Text(context.watch<JarvisService>().statusText, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 12)),
      ]),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  final Message message;
  final bool animate;

  const _MessageBubble({required this.message, this.animate = false});

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  Timer? _typingTimer;
  String _visible = '';

  @override
  void initState() {
    super.initState();
    _visible = widget.animate ? '' : widget.message.content;
    if (widget.animate) _startTyping();
  }

  @override
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.content != oldWidget.message.content || (widget.animate && !oldWidget.animate)) {
      _typingTimer?.cancel();
      _visible = widget.animate ? '' : widget.message.content;
      if (widget.animate) _startTyping();
    }
  }

  void _startTyping() {
    var position = 0;
    final content = widget.message.content;
    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(milliseconds: 18), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      position = position + 5 > content.length ? content.length : position + 5;
      setState(() => _visible = content.substring(0, position));
      if (position >= content.length) {
        timer.cancel();
        _typingTimer = null;
        context.read<JarvisService>().finishResponseTyping();
      }
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    super.dispose();
  }

  Widget _content(String content) {
    final pattern = RegExp(r'\u0060\u0060\u0060([a-zA-Z0-9_+-]*)\s*\n([\s\S]*?)\u0060\u0060\u0060');
    final matches = pattern.allMatches(content).toList();
    if (matches.isEmpty) return SelectableText(content, style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 14, height: 1.65));
    final children = <Widget>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) children.add(SelectableText(content.substring(cursor, match.start), style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 14, height: 1.65)));
      final language = (match.group(1) ?? 'code').toUpperCase();
      final code = (match.group(2) ?? '').trimRight();
      children.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFF080E14), borderRadius: BorderRadius.circular(13), border: Border.all(color: JarvisColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(children: [
              Text(language, style: const TextStyle(color: JarvisColors.cyan, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
                },
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('Copy'),
                style: TextButton.styleFrom(foregroundColor: JarvisColors.textSecondary, visualDensity: VisualDensity.compact),
              ),
            ]),
          ),
          const Divider(height: 1, color: JarvisColors.border),
          SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(14), child: SelectableText(code, style: const TextStyle(color: Color(0xFFD5E7E4), fontFamily: 'monospace', fontSize: 12.5, height: 1.55))),
        ]),
      ));
      cursor = match.end;
    }
    if (cursor < content.length) children.add(SelectableText(content.substring(cursor), style: const TextStyle(color: JarvisColors.textPrimary, fontSize: 14, height: 1.65)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 7, left: 2, right: 2),
            child: Text(isUser ? 'YOU' : 'JARVIS  ·  CASSIMTV', style: TextStyle(color: isUser ? JarvisColors.electricBlue : JarvisColors.cyan, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          ),
          if (isUser)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFF1A2938), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF2C4054))),
              child: _content(_visible),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 12),
              child: _content(_visible),
            ),
          if (widget.message.isError)
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('Something went wrong', style: TextStyle(color: JarvisColors.red, fontSize: 11))),
        ],
      ),
    );
  }
}
