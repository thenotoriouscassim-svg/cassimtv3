import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
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
  final AudioRecorder _recorder = AudioRecorder();
  bool _available = false, _active = false, _busy = false;
  bool _recording = false, _handlingTurn = false;
  String _heard = '', _status = 'Connecting…';
  String? _recordingPath;
  Timer? _recordingLimit;

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
    _recordingLimit?.cancel();
    _sonarCtrl.dispose();
    _pulseCtrl.dispose();
    _waveCtrl.dispose();
    _fadeCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startCall() async {
    try {
      _available = await _recorder.hasPermission();
      if (!_available) { if (mounted) setState(() => _status = 'Microphone permission required. Enable it in Android Settings.'); return; }
      if (!mounted) return;
      setState(() { _active = true; _status = 'Ready — tap the mic and speak'; });
    } catch (error) { if (mounted) setState(() => _status = 'Microphone unavailable: $error'); }
  }

  Future<void> _startRecording() async {
    if (!_active || _busy || _recording || !_available) return;
    try {
      final path = Directory.systemTemp.path + '/jarvis_call_' + DateTime.now().microsecondsSinceEpoch.toString() + '.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000,
        sampleRate: 44100, numChannels: 1, autoGain: true, echoCancel: true, noiseSuppress: true), path: path);
      _recordingPath = path; _recording = true; _heard = '';
      if (mounted) setState(() => _status = 'Recording… tap STOP when finished');
      _recordingLimit?.cancel();
      _recordingLimit = Timer(const Duration(minutes: 3), _stopAndTranscribe);
    } catch (error) {
      debugPrint('JARVIS recording start failed: $error');
      if (mounted) setState(() => _status = 'Could not start recording: $error');
    }
  }

  Future<void> _stopAndTranscribe() async {
    if (!_recording || _handlingTurn) return;
    _recordingLimit?.cancel(); _recording = false; _handlingTurn = true; _busy = true;
    if (mounted) setState(() => _status = 'Preparing your recording…');
    try {
      final path = await _recorder.stop();
      final filePath = path ?? _recordingPath; _recordingPath = null;
      if (filePath == null || !await File(filePath).exists()) throw Exception('The recording file was not created.');
      if (mounted) setState(() => _status = 'Transcribing the full recording…');
      final transcript = await context.read<JarvisService>().transcribeAudio(File(filePath));
      try { await File(filePath).delete(); } catch (_) {}
      if (transcript.trim().isEmpty) throw Exception('No speech could be extracted. Try speaking closer to the phone.');
      _heard = transcript.trim();
      if (mounted) setState(() => _status = 'Heard you — preparing response…');
      await _handleTurn(_heard);
    } catch (error) {
      debugPrint('JARVIS recording transcription failed: $error');
      if (mounted) setState(() => _status = 'Transcription failed: $error. Tap mic to try again.');
    } finally {
      _busy = false; _handlingTurn = false;
      if (_active && mounted && !_recording) setState(() => _status = 'Ready — tap the mic and speak');
    }
  }

  Future<void> _toggleListening() async {
    if (_recording) { await _stopAndTranscribe(); } else { await _startRecording(); }
  }

  Future<void> _handleTurn(String text) async {
    if (!_active || text.trim().isEmpty) return;
    if (mounted) setState(() => _status = 'JARVIS is thinking…');
    try {
      final service = context.read<JarvisService>();
      final spoken = text.trim();
      if (RegExp(r'^jarvis[.!?, ]*$', caseSensitive: false).hasMatch(spoken)) {
        await service.speakText('At your service.');
      } else {
        final command = spoken.replaceFirst(RegExp(r'^jarvis[, ]+', caseSensitive: false), '').trim();
        await service.sendTextMessage(command.isEmpty ? spoken : command, speakResponse: true,
          memoryContext: context.read<MemoryService>().buildMemoryContext());
      }
    } catch (error) {
      debugPrint('JARVIS call turn failed: $error');
      if (mounted) setState(() => _status = 'JARVIS response failed: $error');
    }
  }

  Future<void> _endCall() async {
    _active = false; _recordingLimit?.cancel();
    if (_recording) { _recording = false; await _recorder.stop(); }
    await _recorder.dispose();
    if (mounted) Navigator.of(context).pop();
  }

  Color get _accentColor => !_active ? _C.textDim : (_busy ? _C.amber : _C.cyan);
  bool get _isListening => _active && _recording;

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
                        icon: _recording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: _C.cyan, label: _recording ? 'STOP & SEND' : 'RECORD'),
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
