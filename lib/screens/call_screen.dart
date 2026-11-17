import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/jarvis_service.dart';
import '../services/memory_service.dart';
import '../utils/constants.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;
  bool _active = false;
  bool _busy = false;
  bool _handlingTurn = false;
  String _heard = '';
  String _status = 'Connecting microphone...';
  Timer? _silenceTimer;
  Timer? _restartTimer;
  Timer? _finalizeTimer;
  bool _startingListen = false;
  bool _holdListening = false;

  @override
  void initState() {
    super.initState();
    _startCall();
  }

  Future<void> _startCall() async {
    // Android can still be showing the RECORD_AUDIO permission prompt when
    // Call Mode opens. Give the OS/plugin time to finish that first-run flow,
    // then retry initialisation instead of leaving Call Mode permanently dead.
    if (mounted) setState(() => _status = 'Preparing speech recognition…');

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted) return;
      try {
        _available = await _speech.initialize(
          onStatus: _onSpeechStatus,
          onError: (error) {
            debugPrint('JARVIS Call speech error: ${error.errorMsg}; permanent=${error.permanent}');
            if (!mounted || !_active || _holdListening || _busy || _handlingTurn) return;
            final message = error.errorMsg.toLowerCase();
            final denied = message.contains('permission') || message.contains('not-allowed');
            if (denied || error.permanent) {
              _holdListening = true;
              _silenceTimer?.cancel();
              setState(() => _status = denied
                  ? 'Microphone permission is required. Allow it in Android Settings > Apps > JARVIS AI > Permissions.'
                  : 'Speech recognition stopped: ${error.errorMsg}');
              return;
            }
            if (_heard.trim().isNotEmpty) {
              _handleTurn(_heard.trim());
            } else {
              if (mounted) setState(() => _status = 'Reconnecting microphone…');
              _scheduleListenRestart();
            }
          },
        );
        if (_available) break;
      } catch (error) {
        lastError = error;
        debugPrint('JARVIS Call speech initialisation attempt ${attempt + 1} failed: $error');
      }
      if (attempt < 2) {
        if (mounted) setState(() => _status = 'Waiting for microphone permission…');
        await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
      }
    }

    if (!_available) {
      if (mounted) {
        setState(() => _status = lastError == null
            ? 'Could not start speech recognition. Close and reopen Call Mode to retry.'
            : 'Could not start speech recognition: $lastError');
      }
      return;
    }
    if (mounted) setState(() { _active = true; _status = 'Listening — speak now'; });
    await _listen();
  }

  Future<void> _listen() async {
    if (!_active || _busy || !_available || _startingListen || _speech.isListening) return;
    _startingListen = true;
    _holdListening = false;
    _heard = '';
    if (mounted) setState(() => _status = 'Starting microphone…');
    try {
      await _speech.listen(
        onResult: (result) {
          _heard = result.recognizedWords;
          _armSilenceTimeout();
          if (mounted) setState(() => _status = _heard.isEmpty ? 'Listening — speak now' : 'I heard you…');
          if (result.finalResult) _handleTurn(_heard);
        },
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      );
      // The speech plugin may report isListening a moment after listen() returns.
      // Do not restart here; wait for its status callback to avoid start/stop loops.
      _armSilenceTimeout();
    } catch (error) {
      _holdListening = true;
      if (mounted) setState(() => _status = 'Could not start microphone: $error');
    } finally {
      _startingListen = false;
    }
  }

  void _scheduleListenRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 900), () async {
      if (!_active || _busy || _handlingTurn || _holdListening || !mounted || _startingListen) return;
      // A stale isListening flag can survive an Android recognition error.
      // Explicitly close that session before opening the next one.
      if (_speech.isListening) {
        await _speech.stop();
        await Future.delayed(const Duration(milliseconds: 350));
      }
      if (_active && !_busy && !_handlingTurn && !_holdListening && mounted && !_startingListen) {
        await _listen();
      }
    });
  }

  void _armSilenceTimeout() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(const Duration(seconds: 25), () async {
      if (!_active || _busy || _handlingTurn || !_speech.isListening || _heard.trim().isNotEmpty) return;
      _holdListening = true;
      await _speech.stop();
      if (mounted) setState(() => _status = 'No speech detected. Tap the mic to try again.');
    });
  }

  Future<void> _toggleListening() async {
    if (_speech.isListening) {
      _holdListening = true;
      _silenceTimer?.cancel();
      await _speech.stop();
      if (mounted) setState(() => _status = 'Microphone paused. Tap to resume.');
    } else {
      _holdListening = false;
      await _listen();
    }
  }

  void _onSpeechStatus(String status) {
    if (!_active || !mounted) return;
    if (status == 'listening') {
      _finalizeTimer?.cancel();
      setState(() => _status = 'Listening — speak now');
      return;
    }
    if (status == 'done' || status == 'notListening') {
      _silenceTimer?.cancel();
      if (_holdListening || _handlingTurn || _busy) return;
      final transcript = _heard.trim();
      if (transcript.isNotEmpty) {
        // Do not cut the user off on a short Android silence callback.
        // Give a final recognition result a moment to arrive first.
        _finalizeTimer?.cancel();
        _finalizeTimer = Timer(const Duration(milliseconds: 900), () {
          if (!_active || _holdListening || _busy || _handlingTurn || !mounted) return;
          final latest = _heard.trim();
          if (latest.isNotEmpty) _handleTurn(latest);
          else _scheduleListenRestart();
        });
      } else {
        _scheduleListenRestart();
      }
    }
  }

  Future<void> _handleTurn(String text) async {
    if (_handlingTurn || !_active || text.trim().isEmpty) return;
    _handlingTurn = true;
    _busy = true;
    _holdListening = true;
    _silenceTimer?.cancel();
    _restartTimer?.cancel();
    _finalizeTimer?.cancel();
    await _speech.stop();
    if (mounted) setState(() => _status = 'JARVIS is thinking...');
    try {
      final spoken = text.trim();
      if (RegExp(r'^jarvis[.!?, ]*$', caseSensitive: false).hasMatch(spoken)) {
        await context.read<JarvisService>().speakText('At your service.');
      } else {
        final command = spoken.replaceFirst(RegExp(r'^jarvis[, ]+', caseSensitive: false), '').trim();
        await context.read<JarvisService>().sendTextMessage(command.isEmpty ? spoken : command, speakResponse: true, memoryContext: context.read<MemoryService>().buildMemoryContext());
      }
    } finally {
      _busy = false;
      _handlingTurn = false;
      if (_active && mounted) {
        setState(() => _status = 'Your turn...');
        await Future.delayed(const Duration(milliseconds: 500));
        if (_active && mounted) {
          _holdListening = false;
          await _listen();
        }
      }
    }
  }

  Future<void> _endCall() async {
    _active = false;
    _silenceTimer?.cancel();
    _restartTimer?.cancel();
    await _speech.stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _active = false;
    _silenceTimer?.cancel();
    _restartTimer?.cancel();
    _finalizeTimer?.cancel();
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    return Scaffold(
      backgroundColor: JarvisColors.background,
      appBar: AppBar(
        backgroundColor: JarvisColors.surface,
        foregroundColor: JarvisColors.cyan,
        title: const Text('JARVIS CALL', style: TextStyle(fontFamily: 'Orbitron', letterSpacing: 2, fontSize: 14)),
        actions: [
          IconButton(
            tooltip: 'Return to chat',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.chat_bubble_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: 112, height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: JarvisColors.surfaceLight,
                border: Border.all(color: _busy ? JarvisColors.gold : JarvisColors.cyan, width: 2),
                boxShadow: [BoxShadow(color: (_busy ? JarvisColors.gold : JarvisColors.cyan).withOpacity(.2), blurRadius: 28, spreadRadius: 5)],
              ),
              child: Icon(_busy ? Icons.graphic_eq : Icons.mic, size: 46, color: _busy ? JarvisColors.gold : JarvisColors.cyan),
            ),
            const SizedBox(height: 24),
            Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: JarvisColors.textPrimary, fontFamily: 'Orbitron', fontSize: 13)),
            if (_heard.isNotEmpty) Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_heard, textAlign: TextAlign.center, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 14)),
            ),
            if (jarvis.state == JarvisState.processing || jarvis.state == JarvisState.speaking)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(jarvis.statusText, style: const TextStyle(color: JarvisColors.textDim, fontSize: 10, letterSpacing: 2)),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 42),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _toggleListening,
                    icon: Icon(_speech.isListening ? Icons.mic_off : Icons.mic, color: JarvisColors.cyan, size: 28),
                    style: IconButton.styleFrom(backgroundColor: JarvisColors.surfaceLight, padding: const EdgeInsets.all(18)),
                  ),
                  const SizedBox(width: 42),
                  IconButton(
                    onPressed: _endCall,
                    icon: const Icon(Icons.call_end, color: Colors.white, size: 30),
                    style: IconButton.styleFrom(backgroundColor: JarvisColors.red, padding: const EdgeInsets.all(20)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
