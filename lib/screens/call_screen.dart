import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/jarvis_service.dart';
import '../services/memory_service.dart';

class _C {
  static const bg = Color(0xFF050508);
  static const surface = Color(0xFF0D0D18);
  static const cyan = Color(0xFF00C8FF);
  static const purple = Color(0xFF7B2FFF);
  static const amber = Color(0xFFFFB347);
  static const red = Color(0xFFFF3B5C);
  static const textHi = Color(0xFFE8F4FF);
  static const textMid = Color(0xFF7A9AB8);
  static const textDim = Color(0xFF3A5068);
}

TextStyle _exo({
  Color? color, double? fontSize, FontWeight? weight,
  double? letterSpacing, double? height,
}) => GoogleFonts.exo2(
  color: color, fontSize: fontSize, fontWeight: weight,
  letterSpacing: letterSpacing, height: height,
);

class _SonarPainter extends CustomPainter {
  final double progress;
  final Color color;
  final int rings;
  _SonarPainter({required this.progress, required this.color, this.rings = 4});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width * .48;
    for (var i = 0; i < rings; i++) {
      final phase = (progress + i / rings) % 1.0;
      final paint = Paint()
        ..color = color.withOpacity((1 - phase) * .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, maxR * phase, paint);
    }
  }

  @override
  bool shouldRepaint(_SonarPainter old) =>
      old.progress != progress || old.color != color;
}

class _WavePainter extends CustomPainter {
  final double tick;
  final Color color;
  final bool active;
  _WavePainter({required this.tick, required this.color, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 28;
    final barW = size.width / (bars * 2 - 1);
    final paint = Paint()
      ..color = color.withOpacity(active ? .85 : .25)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barW;
    for (var i = 0; i < bars; i++) {
      final x = i * barW * 2 + barW / 2;
      final h = active
          ? size.height * (.15 + .65 * math.pow(math.sin(tick * 3.5 + i * .55).abs(), .6))
          : size.height * (.08 + .12 * math.sin(i * .8).abs());
      final cy = size.height / 2;
      canvas.drawLine(Offset(x, cy - h / 2), Offset(x, cy + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.tick != tick || old.active != active || old.color != color;
}

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false, _active = false, _busy = false;
  bool _handlingTurn = false, _startingListen = false;
  bool _restartInProgress = false, _holdListening = false;
  String _heard = '', _status = 'Connecting…';
  Timer? _silenceTimer, _restartTimer, _finalizeTimer;
  DateTime? _lastListenStarted;

  late final AnimationController _sonarCtrl, _pulseCtrl, _waveCtrl, _fadeCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _sonarCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
    // A slower cycle keeps the waveform fluid instead of flickering at 60 ms.
    _waveCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400), value: 0)..forward();
    _pulseAnim = Tween<double>(begin: .92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _startCall();
  }

  @override
  void dispose() {
    _active = false;
    _silenceTimer?.cancel();
    _restartTimer?.cancel();
    _finalizeTimer?.cancel();
    _sonarCtrl.dispose();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    _fadeCtrl.dispose();
    _speech.cancel();
    super.dispose();
  }

  Future<void> _startCall() async {
    if (mounted) setState(() => _status = 'Preparing voice engine…');
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted) return;
      try {
        _available = await _speech.initialize(
          onStatus: _onSpeechStatus,
          onError: (error) {
            debugPrint('JARVIS Call speech error: ${error.errorMsg}; permanent=${error.permanent}');
            if (!mounted || !_active || _holdListening || _busy || _handlingTurn) return;
            final msg = error.errorMsg.toLowerCase();
            final denied = msg.contains('permission') || msg.contains('not-allowed');
            final noMatch = msg.contains('no_match') || msg.contains('no match') ||
                msg.contains('speech_timeout') || msg.contains('speech timeout');
            final busy = msg.contains('busy') || msg.contains('client');
            if (denied || (error.permanent && !noMatch && !busy)) {
              _holdListening = true;
              _silenceTimer?.cancel();
              setState(() => _status = denied
                  ? 'Microphone permission required. Enable it in Settings → Apps → JARVIS → Permissions.'
                  : 'Speech unavailable: ${error.errorMsg}');
              return;
            }
            if (_heard.trim().isNotEmpty) {
              _handleTurn(_heard.trim());
            } else {
              if (mounted) setState(() => _status = busy ? 'Releasing microphone…' : 'Speak when ready');
              _scheduleListenRestart(busy ? const Duration(milliseconds: 1800) : const Duration(milliseconds: 900));
            }
          },
        );
        if (_available) break;
      } catch (error) {
        lastError = error;
        debugPrint('JARVIS Call init attempt ${attempt + 1} failed: $error');
      }
      if (attempt < 2) {
        if (mounted) setState(() => _status = 'Waiting for microphone permission…');
        await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
      }
    }
    if (!_available) {
      if (mounted) setState(() => _status = lastError == null
          ? 'Could not start voice recognition. Close and reopen Call Mode to retry.'
          : 'Could not start voice recognition: $lastError');
      return;
    }
    if (mounted) setState(() { _active = true; _status = 'Listening'; });
    await _listen();
  }

  Future<void> _listen() async {
    if (!_active || _busy || !_available || _startingListen || _restartInProgress || _speech.isListening) return;
    final lastStart = _lastListenStarted;
    if (lastStart != null) {
      final elapsed = DateTime.now().difference(lastStart);
      if (elapsed < const Duration(milliseconds: 1100)) {
        await Future.delayed(const Duration(milliseconds: 1100) - elapsed);
        if (!_active || _busy || _holdListening || !mounted || _speech.isListening) return;
      }
    }
    _startingListen = true;
    _holdListening = false;
    _heard = '';
    if (mounted) setState(() => _status = 'Activating mic…');
    try {
      _lastListenStarted = DateTime.now();
      await _speech.listen(
        onResult: (result) {
          _heard = result.recognizedWords;
          if (_heard.trim().isNotEmpty) _armSilenceTimeout();
          if (mounted) setState(() => _status = _heard.isEmpty ? 'Listening' : 'Got it…');
          if (result.finalResult && _heard.trim().isNotEmpty) _handleTurn(_heard.trim());
        },
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 8),
        partialResults: true,
        cancelOnError: false,
        listenMode: stt.ListenMode.dictation,
      );
      _armSilenceTimeout();
    } catch (error) {
      final msg = error.toString().toLowerCase();
      if (msg.contains('busy')) {
        if (mounted) setState(() => _status = 'Releasing microphone…');
        _scheduleListenRestart(const Duration(milliseconds: 1800));
      } else {
        if (mounted) setState(() => _status = 'Reconnecting mic…');
        _scheduleListenRestart(const Duration(milliseconds: 1200));
      }
    } finally {
      _startingListen = false;
    }
  }

  void _scheduleListenRestart([Duration delay = const Duration(milliseconds: 1100)]) {
    if (_restartInProgress || _holdListening) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () async {
      if (!_active || _busy || _handlingTurn || _holdListening || !mounted || _startingListen || _restartInProgress) return;
      _restartInProgress = true;
      try {
        if (_speech.isListening) {
          await _speech.stop();
          await Future.delayed(const Duration(milliseconds: 700));
        } else {
          await Future.delayed(const Duration(milliseconds: 1200));
        }
      } finally {
        _restartInProgress = false;
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
      if (mounted) setState(() => _status = 'No speech detected — tap mic to retry');
    });
  }

  Future<void> _toggleListening() async {
    if (_speech.isListening) {
      _holdListening = true;
      _silenceTimer?.cancel();
      await _speech.stop();
      if (mounted) setState(() => _status = 'Mic paused — tap to resume');
    } else {
      _holdListening = false;
      await _listen();
    }
  }

  void _onSpeechStatus(String status) {
    if (!_active || !mounted) return;
    if (status == 'listening') {
      _finalizeTimer?.cancel();
      setState(() => _status = 'Listening');
      return;
    }
    if (status == 'done' || status == 'notListening') {
      _silenceTimer?.cancel();
      if (_holdListening || _handlingTurn || _busy) return;
      if (_heard.trim().isNotEmpty) {
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
    var responseSucceeded = false;
    await _speech.stop();
    await Future.delayed(const Duration(milliseconds: 450));
    if (mounted) setState(() => _status = 'Processing…');
    try {
      final service = context.read<JarvisService>();
      final spoken = text.trim();
      if (RegExp(r'^jarvis[.!?, ]*$', caseSensitive: false).hasMatch(spoken)) {
        await service.speakText('At your service.');
        responseSucceeded = service.lastSpeechSucceeded;
      } else {
        final command = spoken.replaceFirst(RegExp(r'^jarvis[, ]+', caseSensitive: false), '').trim();
        await service.sendTextMessage(
          command.isEmpty ? spoken : command,
          speakResponse: true,
          memoryContext: context.read<MemoryService>().buildMemoryContext(),
        );
        responseSucceeded = service.lastSpeechSucceeded;
        if (!responseSucceeded) {
          final last = service.conversation.isNotEmpty ? service.conversation.last : null;
          if (last?.isError == true && mounted) {
            setState(() => _status = 'Cloud response failed — tap mic to retry');
          }
        }
      }
    } catch (error) {
      debugPrint('JARVIS call turn failed: $error');
      responseSucceeded = false;
    } finally {
      _busy = false;
      _handlingTurn = false;
      if (_active && mounted) {
        if (responseSucceeded) {
          setState(() => _status = 'Your turn…');
          await Future.delayed(const Duration(milliseconds: 500));
          if (_active && mounted) {
            _holdListening = false;
            await _listen();
          }
        } else {
          _holdListening = true;
          setState(() => _status = 'No spoken reply — tap mic to retry');
        }
      }
    }
  }

  Future<void> _endCall() async {
    _active = false;
    _silenceTimer?.cancel();
    _restartTimer?.cancel();
    _finalizeTimer?.cancel();
    await _speech.stop();
    if (mounted) Navigator.of(context).pop();
  }

  Color get _accentColor => !_active ? _C.textDim : (_busy ? _C.amber : _C.cyan);
  bool get _isListening => _active && !_busy && _speech.isListening;

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    final size = MediaQuery.of(context).size;
    final orbSize = math.min(size.width * .72, size.height * .40);
    return Scaffold(
      backgroundColor: _C.bg,
      body: FadeTransition(
        opacity: _fadeCtrl,
        child: Stack(
          children: [
            Positioned.fill(child: _GridBackground()),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    _GlassButton(
                      onTap: () => Navigator.of(context).pop(),
                      child: Row(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.chevron_left, color: _C.textMid, size: 18),
                        SizedBox(width: 4),
                        Text('CHAT', style: TextStyle(color: _C.textMid, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    const Spacer(),
                    Text('JARVIS', style: _exo(color: _C.textHi, fontSize: 15, weight: FontWeight.w700, letterSpacing: 4)),
                    const Spacer(),
                    _LiveDot(active: _active && !_busy),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 72),
                  const Spacer(),
                  AnimatedBuilder(
                    animation: Listenable.merge([_sonarCtrl, _pulseCtrl]),
                    builder: (context, _) {
                      final scale = _isListening ? _pulseAnim.value : 1.0;
                      return SizedBox(
                        width: orbSize,
                        height: orbSize,
                        child: Stack(alignment: Alignment.center, children: [
                          if (_isListening || _busy)
                            Positioned.fill(child: CustomPaint(
                              painter: _SonarPainter(progress: _sonarCtrl.value, color: _accentColor, rings: 5),
                            )),
                          Container(
                            width: orbSize * .72,
                            height: orbSize * .72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _accentColor.withOpacity(.18)),
                              boxShadow: [BoxShadow(color: _accentColor.withOpacity(_isListening ? .22 : .08), blurRadius: 60, spreadRadius: 12)],
                            ),
                          ),
                          Transform.scale(
                            scale: scale,
                            child: Container(
                              width: orbSize * .53,
                              height: orbSize * .53,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: _busy ? [_C.amber.withOpacity(.22), _C.surface, _C.bg] : [_C.cyan.withOpacity(.18), _C.surface, _C.bg],
                                  stops: const [0, .55, 1],
                                ),
                                border: Border.all(color: _accentColor.withOpacity(.55), width: 1.5),
                                boxShadow: [BoxShadow(color: _accentColor.withOpacity(.35), blurRadius: 32, spreadRadius: 2)],
                              ),
                              child: Icon(_busy ? Icons.graphic_eq_rounded : Icons.mic_rounded, size: orbSize * .14, color: _accentColor),
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  AnimatedBuilder(
                    animation: _waveCtrl,
                    builder: (context, _) => SizedBox(
                      height: 42,
                      width: size.width * .65,
                      child: CustomPaint(painter: _WavePainter(tick: _waveCtrl.value * math.pi * 2, color: _accentColor, active: _isListening)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(_status, key: ValueKey(_status), textAlign: TextAlign.center,
                      style: _exo(color: _busy ? _C.amber : _C.textMid, fontSize: 13, weight: FontWeight.w500, letterSpacing: 1.6)),
                  ),
                  if (jarvis.state == JarvisState.processing || jarvis.state == JarvisState.speaking)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(jarvis.statusText.toUpperCase(), style: _exo(color: _C.purple, fontSize: 10, weight: FontWeight.w600, letterSpacing: 2.5)),
                    ),
                  const Spacer(),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                    child: _heard.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              decoration: BoxDecoration(
                                color: _C.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _C.cyan.withOpacity(.15)),
                              ),
                              child: Text(_heard, textAlign: TextAlign.center,
                                style: _exo(color: _C.textHi, fontSize: 15, height: 1.5)),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 48),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _ActionButton(onTap: _toggleListening,
                        icon: _speech.isListening ? Icons.mic_off_rounded : Icons.mic_rounded,
                        color: _C.cyan, label: _speech.isListening ? 'MUTE' : 'UNMUTE'),
                      const SizedBox(width: 48),
                      _ActionButton(onTap: _endCall, icon: Icons.call_end_rounded, color: _C.red, label: 'END', primary: true),
                    ]),
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

class _GridBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter(), child: const SizedBox.expand());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _C.cyan.withOpacity(.045);
    const step = 32.0;
    for (double x = step; x < size.width; x += step) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }
  @override
  bool shouldRepaint(_GridPainter old) => false;
}

class _LiveDot extends StatefulWidget {
  final bool active;
  const _LiveDot({required this.active});
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.active ? Color.lerp(_C.cyan, _C.purple, _ctrl.value)! : _C.textDim,
        boxShadow: widget.active ? [BoxShadow(color: _C.cyan.withOpacity(.6 * _ctrl.value), blurRadius: 6)] : [],
      )),
      const SizedBox(width: 6),
      Text(widget.active ? 'LIVE' : 'IDLE',
        style: _exo(color: widget.active ? _C.cyan : _C.textDim, fontSize: 10, weight: FontWeight.w700, letterSpacing: 2)),
    ]),
  );
}

class _GlassButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _GlassButton({required this.onTap, required this.child});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.textMid.withOpacity(.2)),
      ),
      child: child,
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color color;
  final String label;
  final bool primary;
  const _ActionButton({required this.onTap, required this.icon, required this.color, required this.label, this.primary = false});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: primary ? 68 : 56,
        height: primary ? 68 : 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primary ? color : _C.surface,
          border: Border.all(color: primary ? Colors.transparent : color.withOpacity(.45), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(primary ? .45 : .25), blurRadius: primary ? 24 : 16)],
        ),
        child: Icon(icon, color: primary ? Colors.white : color, size: primary ? 30 : 24),
      ),
      const SizedBox(height: 8),
      Text(label, style: _exo(color: color.withOpacity(.7), fontSize: 10, weight: FontWeight.w600, letterSpacing: 2)),
    ]),
  );
}
