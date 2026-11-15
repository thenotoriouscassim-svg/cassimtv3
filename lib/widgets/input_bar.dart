import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import '../services/jarvis_service.dart';
import '../utils/constants.dart';

class InputBar extends StatefulWidget {
  const InputBar({super.key});

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  Timer? _recordingTimer;
  String? _recordingPath;
  String? _lastSavedRecordingPath;
  bool _recorderReady = false;
  bool _hasText = false;
  bool _isListening = false;
  bool _isStartingListening = false;


  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    _initializeRecorder();
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
    _recordingTimer?.cancel();
    if (_recorderReady) _recorder.closeRecorder();
    super.dispose();
  }

  void _send(JarvisService jarvis) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    jarvis.sendTextMessage(text);
    _controller.clear();
  }

  Future<void> _initializeRecorder() async {
    try {
      await _recorder.openRecorder();
      if (mounted) setState(() => _recorderReady = true);
    } catch (error) {
      if (mounted) _showMessage('Microphone could not initialize: $error');
    }
  }

  Future<void> _toggleListening() async {
    if (_isStartingListening || !_recorderReady) {
      if (!_recorderReady) _showMessage('Microphone is still initializing. Please try again.');
      return;
    }

    if (_isListening) {
      await _finishRecording();
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
          onAction: permission.isPermanentlyDenied ? () => openAppSettings() : null,
        );
        return;
      }

      final documents = await getApplicationDocumentsDirectory();
      final recordingsDir = Directory('${documents.path}/recordings');
      await recordingsDir.create(recursive: true);
      _recordingPath = '${recordingsDir.path}/jarvis_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.startRecorder(
        toFile: _recordingPath,
        codec: Codec.pcm16WAV,
        sampleRate: 16000,
        numChannels: 1,
      );
      if (!mounted) return;
      setState(() => _isListening = true);
      // Prevent unexpectedly long uploads; user can tap the mic again to finish sooner.
      _recordingTimer?.cancel();
      _recordingTimer = Timer(const Duration(seconds: 25), _finishRecording);
    } catch (error) {
      if (mounted) {
        setState(() => _isListening = false);
        _showMessage('Could not start microphone recording: $error');
      }
    } finally {
      if (mounted) setState(() => _isStartingListening = false);
    }
  }

  Future<void> _finishRecording() async {
    if (!_isListening) return;
    _recordingTimer?.cancel();
    if (mounted) {
      setState(() {
        _isListening = false;
        _isStartingListening = true;
      });
    }
    try {
      final returnedPath = await _recorder.stopRecorder();
      // Some Android devices finish flushing the WAV header just after stopRecorder returns.
      await Future.delayed(const Duration(milliseconds: 250));
      final candidates = <String?>[returnedPath, _recordingPath]
          .whereType<String>()
          .where((path) => path.isNotEmpty)
          .toSet();
      File? savedFile;
      for (final candidate in candidates) {
        final file = File(candidate);
        if (await file.exists() && await file.length() >= 1000) {
          savedFile = file;
          break;
        }
      }
      if (savedFile == null) {
        throw Exception('Android did not create the WAV recording. Check microphone permission and try again.');
      }
      _lastSavedRecordingPath = savedFile.path;
      if (!mounted) return;
      _showMessage('Recording saved. Transcribing...');
      final jarvis = context.read<JarvisService>();
      final transcript = await jarvis.transcribeAudio(savedFile);
      if (!mounted) return;
      _controller.text = transcript;
      jarvis.sendTextMessage(transcript);
      _controller.clear();
    } catch (error) {
      if (mounted) {
        final saved = _lastSavedRecordingPath;
        final suffix = saved == null ? '' : ' Recording kept at: $saved';
        _showMessage('Speech input failed: ${error.toString().replaceFirst('Exception: ', '')}.$suffix');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStartingListening = false;
          _isListening = false;
        });
      }
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
          // Tap-to-talk microphone. Audio is transcribed by the cloud speech endpoint.
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
                      ? 'Recording... tap to send'
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
