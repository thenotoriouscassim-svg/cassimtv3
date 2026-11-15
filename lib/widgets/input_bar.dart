import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/jarvis_service.dart';
import '../utils/constants.dart';

class InputBar extends StatefulWidget {
  const InputBar({super.key});

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _hasText = false;
  bool _isListening = false;
  bool _isStartingListening = false;
  bool _speechAvailable = false;

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
    _speech.stop();
    super.dispose();
  }

  void _send(JarvisService jarvis) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    jarvis.sendTextMessage(text);
    _controller.clear();
  }

  Future<void> _toggleListening() async {
    if (_isStartingListening) return;

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    setState(() => _isStartingListening = true);

    try {
      final permission = await Permission.microphone.request();
      if (!mounted) return;

      if (!permission.isGranted) {
        _showMessage(
          permission.isPermanentlyDenied
              ? 'Microphone permission is blocked. Enable it in Android app settings.'
              : 'Microphone permission is required for voice input.',
          action: permission.isPermanentlyDenied ? 'Settings' : null,
          onAction: permission.isPermanentlyDenied
              ? () => openAppSettings()
              : null,
        );
        return;
      }

      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'notListening' || status == 'done') {
            setState(() => _isListening = false);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() => _isListening = false);
          _showMessage('Speech recognition error: ${error.errorMsg}');
        },
      );

      if (!mounted) return;

      if (!_speechAvailable) {
        _showMessage(
          'Speech recognition is unavailable. Check that a speech service is installed and enabled on this device.',
        );
        return;
      }

      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _controller.value = TextEditingValue(
              text: result.recognizedWords,
              selection: TextSelection.collapsed(
                offset: result.recognizedWords.length,
              ),
            );
          });
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        cancelOnError: true,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _isListening = false);
        _showMessage('Could not start voice input: $error');
      }
    } finally {
      if (mounted) setState(() => _isStartingListening = false);
    }
  }

  void _showMessage(
    String message, {
    String? action,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action != null && onAction != null
              ? SnackBarAction(label: action, onPressed: onAction)
              : null,
        ),
      );
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
          // Tap-to-talk microphone. Speech is transcribed on-device by
          // Android's configured speech recognition service.
          GestureDetector(
            onTap: _isStartingListening ? null : _toggleListening,
            child: AnimatedContainer(
              duration: JarvisDurations.fast,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isListening
                    ? JarvisColors.green.withOpacity(0.15)
                    : Colors.transparent,
                border: Border.all(
                  color: _isListening
                      ? JarvisColors.green
                      : JarvisColors.cyanDim,
                  width: 1.5,
                ),
                boxShadow: _isListening
                    ? [
                        BoxShadow(
                          color: JarvisColors.green.withOpacity(0.4),
                          blurRadius: 12,
                        )
                      ]
                    : null,
              ),
              child: _isStartingListening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening
                          ? JarvisColors.green
                          : JarvisColors.cyanDim,
                      size: 20,
                    ),
            ),
          ),
          const SizedBox(width: 10),

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
                  hintText: _isListening
                      ? 'Listening... speak now'
                      : jarvis.isConnected
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
