import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../services/memory_service.dart';
import '../models/message.dart';

class _C {
  static const bg = Color(0xFF050508);
  static const surface = Color(0xFF0D0D18);
  static const cyan = Color(0xFF00C8FF);
  static const purple = Color(0xFF7B2FFF);
  static const red = Color(0xFFFF3B5C);
  static const green = Color(0xFF45D6A2);
  static const textHi = Color(0xFFE8F4FF);
  static const textMid = Color(0xFF7A9AB8);
  static const textDim = Color(0xFF3A5068);
}

TextStyle _exo({
  Color? color,
  double? fontSize,
  FontWeight? weight,
  double? letterSpacing,
  double? height,
}) => GoogleFonts.exo2(
  color: color,
  fontSize: fontSize,
  fontWeight: weight,
  letterSpacing: letterSpacing,
  height: height,
);

class ConversationPanel extends StatefulWidget {
  const ConversationPanel({super.key});

  @override
  State<ConversationPanel> createState() => _ConversationPanelState();
}

class _ConversationPanelState extends State<ConversationPanel> {
  final ScrollController _scroll = ScrollController();
  int _lastCount = 0;
  int _lastContentLength = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _sendPrompt(BuildContext context, String prompt) {
    final jarvis = context.read<JarvisService>();
    final memory = context.read<MemoryService>();
    jarvis.sendTextMessage(
      prompt,
      memoryContext: memory.buildMemoryContext(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    final messages = jarvis.conversation;
    final latestLength = messages.isEmpty ? 0 : messages.last.content.length;
    if (messages.length > _lastCount || latestLength > _lastContentLength) {
      _scrollToBottom();
    }
    _lastCount = messages.length;
    _lastContentLength = latestLength;

    if (messages.isEmpty) return _buildWelcome(context);

    return Container(
      color: _C.bg,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 32),
        itemCount: messages.length +
            (jarvis.state == JarvisState.processing ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return const _ThinkingIndicator();
          }
          return _MessageRow(
            message: messages[index],
            animate: jarvis.isTypingResponse &&
                index == messages.length - 1,
          );
        },
      ),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final suggestions = [
      (Icons.code_rounded, 'BUILD SOMETHING', 'Help me build an app'),
      (Icons.travel_explore_rounded, 'RESEARCH', 'Research the latest technology news'),
      (Icons.lightbulb_outline_rounded, 'THINK IT THROUGH', 'Help me plan a new project'),
    ];

    return Container(
      color: _C.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 38),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _C.surface,
                    border: Border.all(color: _C.cyan.withOpacity(.55)),
                    boxShadow: [
                      BoxShadow(
                        color: _C.cyan.withOpacity(.16),
                        blurRadius: 34,
                        spreadRadius: 3,
                      ),
                      BoxShadow(
                        color: _C.purple.withOpacity(.12),
                        blurRadius: 48,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'J',
                      style: _exo(
                        color: _C.cyan,
                        fontSize: 42,
                        weight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 25),
                Text(
                  'What do you need?',
                  textAlign: TextAlign.center,
                  style: _exo(
                    color: _C.textHi,
                    fontSize: 29,
                    weight: FontWeight.w700,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your assistant is ready. Ask, create, explore, or get things done.',
                  textAlign: TextAlign.center,
                  style: _exo(
                    color: _C.textMid,
                    fontSize: 13,
                    height: 1.6,
                    weight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 32),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: suggestions.map((item) {
                    return SizedBox(
                      width: 195,
                      child: _SuggestionTile(
                        icon: item.$1,
                        title: item.$2,
                        onTap: () => _sendPrompt(context, item.$3),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 30),
                Text(
                  'JARVIS AI  /  CASSIMTV',
                  style: _exo(
                    color: _C.textDim,
                    fontSize: 9,
                    weight: FontWeight.w700,
                    letterSpacing: 2.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFF111321) : _C.surface,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: _hovered ? _C.cyan.withOpacity(.48) : _C.textDim.withOpacity(.32),
          ),
          boxShadow: _hovered
              ? [BoxShadow(color: _C.cyan.withOpacity(.10), blurRadius: 20)]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(widget.icon, color: _C.cyan, size: 21),
                  const SizedBox(height: 17),
                  Text(
                    widget.title,
                    style: _exo(
                      color: _C.textHi,
                      fontSize: 11,
                      weight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Start a conversation',
                    style: _exo(color: _C.textDim, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator();

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<JarvisService>().statusText;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 20, left: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _C.surface,
              border: Border.all(color: _C.purple.withOpacity(.45)),
            ),
            child: const Icon(Icons.auto_awesome, color: _C.cyan, size: 15),
          ),
          const SizedBox(width: 11),
          Text(
            status.isEmpty ? 'JARVIS is thinking' : status,
            style: _exo(color: _C.textMid, fontSize: 12, weight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) => Row(
              children: List.generate(3, (index) {
                final phase = (_controller.value + index * .22) % 1;
                final opacity = .25 + (.75 * (1 - (phase - .5).abs() * 2));
                return Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _C.cyan.withOpacity(opacity),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final Message message;
  final bool animate;

  const _MessageRow({required this.message, required this.animate});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 31,
              height: 31,
              margin: const EdgeInsets.only(right: 11, top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _C.surface,
                border: Border.all(color: _C.cyan.withOpacity(.45)),
                boxShadow: [
                  BoxShadow(color: _C.cyan.withOpacity(.08), blurRadius: 12),
                ],
              ),
              child: Center(
                child: Text(
                  'J',
                  style: _exo(
                    color: _C.cyan,
                    fontSize: 17,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Column(
                crossAxisAlignment: isUser
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7, left: 2, right: 2),
                    child: Text(
                      isUser ? 'YOU' : 'JARVIS  /  CASSIMTV',
                      style: _exo(
                        color: isUser ? _C.purple : _C.cyan,
                        fontSize: 9,
                        weight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ),
                  if (isUser)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111522),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: _C.purple.withOpacity(.28)),
                      ),
                      child: _MessageContent(
                        content: message.content,
                        animate: animate,
                        userMessage: true,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 2, right: 10),
                      child: _MessageContent(
                        content: message.content,
                        animate: animate,
                        userMessage: false,
                      ),
                    ),
                  if (message.isError)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Text(
                        'Something went wrong',
                        style: _exo(color: _C.red, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageContent extends StatefulWidget {
  final String content;
  final bool animate;
  final bool userMessage;

  const _MessageContent({
    required this.content,
    required this.animate,
    required this.userMessage,
  });

  @override
  State<_MessageContent> createState() => _MessageContentState();
}

class _MessageContentState extends State<_MessageContent> {
  Timer? _typingTimer;
  String _visible = '';

  @override
  void initState() {
    super.initState();
    _visible = widget.animate ? '' : widget.content;
    if (widget.animate) _startTyping();
  }

  @override
  void didUpdateWidget(covariant _MessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content ||
        (widget.animate && !oldWidget.animate)) {
      _typingTimer?.cancel();
      _visible = widget.animate ? '' : widget.content;
      if (widget.animate) _startTyping();
    }
  }

  void _startTyping() {
    var position = 0;
    final content = widget.content;
    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(milliseconds: 18), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      position = (position + 5).clamp(0, content.length).toInt();
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

  Widget _text(String value) => SelectableText(
        value,
        style: _exo(
          color: _C.textHi,
          fontSize: 14,
          height: 1.7,
          weight: FontWeight.w400,
        ),
      );

  Widget _content(String value) {
    // Match completed and still-streaming fenced blocks so the code panel\n    // appears as soon as the opening fence and first newline arrive.\n    final pattern = RegExp(r'```([a-zA-Z0-9_+-]*)[ \\t]*\\n([\\s\\S]*?)(?:```|$)');
    final matches = pattern.allMatches(value).toList();
    if (matches.isEmpty) return _text(value);

    final children = <Widget>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        children.add(_text(value.substring(cursor, match.start)));
      }
      final language = (match.group(1) ?? 'code').toUpperCase();
      final code = (match.group(2) ?? '').trimRight();
      children.add(_CodeBlock(language: language, code: code));
      cursor = match.end;
    }
    if (cursor < value.length) children.add(_text(value.substring(cursor)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _content(_visible);
  }
}

class _CodeBlock extends StatefulWidget {
  final String language;
  final String code;

  const _CodeBlock({required this.language, required this.code});

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;
  final ScrollController _codeScroll = ScrollController();

  @override
  void didUpdateWidget(covariant _CodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.code.length > oldWidget.code.length) _scrollCodeToBottom();
  }

  void _scrollCodeToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _codeScroll.hasClients) {
        _codeScroll.animateTo(
          _codeScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _codeScroll.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF090B12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.textDim.withOpacity(.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Icon(Icons.code_rounded, color: _C.cyan.withOpacity(.8), size: 15),
                const SizedBox(width: 8),
                Text(
                  widget.language,
                  style: _exo(
                    color: _C.cyan,
                    fontSize: 10,
                    weight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _copy,
                  icon: Icon(
                    _copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 14,
                  ),
                  label: Text(_copied ? 'COPIED' : 'COPY'),
                  style: TextButton.styleFrom(
                    foregroundColor: _copied ? _C.green : _C.textMid,
                    textStyle: _exo(
                      fontSize: 9,
                      weight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _C.textDim.withOpacity(.35)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              controller: _codeScroll,
              padding: const EdgeInsets.all(14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  widget.code,
                  style: const TextStyle(
                    color: Color(0xFFD5E7F2),
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
