import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../utils/constants.dart';

class JarvisCoreWidget extends StatefulWidget {
  const JarvisCoreWidget({super.key});
  @override
  State<JarvisCoreWidget> createState() => _JarvisCoreWidgetState();
}

class _JarvisCoreWidgetState extends State<JarvisCoreWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotateController;
  late Animation<double> _pulseAnim;
  late Animation<double> _rotateAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _rotateAnim = Tween<double>(begin: 0, end: 2 * pi).animate(_rotateController);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    final state  = jarvis.state;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnim, _rotateAnim]),
      builder: (context, _) {
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow rings
              _buildGlowRing(160, JarvisColors.cyan.withOpacity(0.08), 0),
              _buildGlowRing(140, JarvisColors.cyan.withOpacity(0.12), 0),

              // Rotating arc ring
              Transform.rotate(
                angle: _rotateAnim.value,
                child: CustomPaint(
                  size: const Size(130, 130),
                  painter: _ArcRingPainter(
                    color: JarvisColors.cyan,
                    state: state,
                  ),
                ),
              ),

              // Counter-rotating arc
              Transform.rotate(
                angle: -_rotateAnim.value * 0.6,
                child: CustomPaint(
                  size: const Size(110, 110),
                  painter: _ArcRingPainter(
                    color: JarvisColors.electricBlue,
                    state: state,
                    dashOffset: 0.5,
                  ),
                ),
              ),

              // Pulsing core circle
              Transform.scale(
                scale: state == JarvisState.standby ? _pulseAnim.value : 1.0,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: JarvisColors.background,
                    border: Border.all(
                      color: _stateColor(state),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _stateColor(state).withOpacity(0.5),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'J',
                          style: TextStyle(
                            color: _stateColor(state),
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Orbitron',
                            shadows: [
                              Shadow(
                                color: _stateColor(state).withOpacity(0.8),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Status label below core
              Positioned(
                bottom: 8,
                child: Column(
                  children: [
                    _buildStateIndicator(state),
                    const SizedBox(height: 4),
                    Text(
                      jarvis.statusText,
                      style: TextStyle(
                        color: _stateColor(state),
                        fontSize: 10,
                        letterSpacing: 4,
                        fontFamily: 'Orbitron',
                        shadows: [
                          Shadow(
                            color: _stateColor(state).withOpacity(0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // JARVIS AI label above
              Positioned(
                top: 8,
                child: Column(
                  children: [
                    Text(
                      'JARVIS AI',
                      style: TextStyle(
                        color: JarvisColors.cyan,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                        fontFamily: 'Orbitron',
                        shadows: [
                          Shadow(color: JarvisColors.cyan.withOpacity(0.6), blurRadius: 10),
                        ],
                      ),
                    ),
                    Text(
                      'by CassimTV',
                      style: TextStyle(
                        color: JarvisColors.textSecondary,
                        fontSize: 8,
                        letterSpacing: 3,
                        fontFamily: 'Orbitron',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGlowRing(double size, Color color, double extraBlur) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: JarvisColors.cyan.withOpacity(0.1), blurRadius: 20 + extraBlur),
        ],
      ),
    );
  }

  Widget _buildStateIndicator(JarvisState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _stateColor(state),
            boxShadow: [
              BoxShadow(color: _stateColor(state), blurRadius: 6),
            ],
          ),
        ),
      ],
    );
  }

  Color _stateColor(JarvisState state) => switch (state) {
    JarvisState.standby          => JarvisColors.cyanDim,
    JarvisState.processing       => JarvisColors.electricBlue,
    JarvisState.speaking         => JarvisColors.cyan,
  };
}

class _ArcRingPainter extends CustomPainter {
  final Color color;
  final JarvisState state;
  final double dashOffset;

  _ArcRingPainter({
    required this.color,
    required this.state,
    this.dashOffset = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint  = Paint()
      ..color       = color
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap   = StrokeCap.round;

    // Draw dashed arcs
    const segments = 8;
    final segAngle  = (2 * pi) / segments;
    final gapAngle  = segAngle * 0.35;
    final arcAngle  = segAngle - gapAngle;

    for (int i = 0; i < segments; i++) {
      final startAngle = i * segAngle + dashOffset * pi;
      paint.color = color.withOpacity(
        state == JarvisState.speaking
            ? 1.0
            : 0.6,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 2),
        startAngle,
        arcAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcRingPainter old) =>
      old.state != state || old.color != color;
}
