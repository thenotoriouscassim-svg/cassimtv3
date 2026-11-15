import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../utils/constants.dart';

class StatusBarWidget extends StatelessWidget {
  const StatusBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: JarvisColors.surface,
        border: Border(bottom: BorderSide(color: JarvisColors.border)),
      ),
      child: Row(
        children: [
          // Brand
          RichText(
            text: TextSpan(
              children: [
                TextSpan(text: 'JARVIS AI ', style: TextStyle(
                  color: JarvisColors.cyan, fontSize: 11,
                  fontWeight: FontWeight.bold, letterSpacing: 3,
                  fontFamily: 'Orbitron',
                  shadows: [Shadow(color: JarvisColors.cyan.withOpacity(0.6), blurRadius: 8)],
                )),
                const TextSpan(text: 'by CassimTV', style: TextStyle(
                  color: JarvisColors.textSecondary, fontSize: 8,
                  letterSpacing: 2, fontFamily: 'Orbitron',
                )),
              ],
            ),
          ),

          const Spacer(),

          // Connection indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(
                color: jarvis.isConnected ? JarvisColors.green : JarvisColors.red,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 4, height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: jarvis.isConnected ? JarvisColors.green : JarvisColors.red,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  jarvis.isConnected ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    color: jarvis.isConnected ? JarvisColors.green : JarvisColors.red,
                    fontSize: 8, letterSpacing: 1, fontFamily: 'Orbitron',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          // Large, accessible mute toggle hit target.
          Tooltip(
            message: jarvis.autoSpeak ? 'Mute JARVIS voice' : 'Unmute JARVIS voice',
            child: Material(
              color: jarvis.autoSpeak
                  ? JarvisColors.cyan.withOpacity(0.10)
                  : JarvisColors.red.withOpacity(0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: jarvis.autoSpeak ? JarvisColors.cyanDim : JarvisColors.red,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => jarvis.setAutoSpeak(!jarvis.autoSpeak),
                child: SizedBox(
                  width: 48,
                  height: 44,
                  child: Icon(
                    jarvis.autoSpeak ? Icons.volume_up : Icons.volume_off,
                    color: jarvis.autoSpeak ? JarvisColors.cyan : JarvisColors.red,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Retry connection
          if (!jarvis.isConnected)
            GestureDetector(
              onTap: jarvis.retryConnection,
              child: const Icon(Icons.refresh, color: JarvisColors.textSecondary, size: 16),
            ),
        ],
      ),
    );
  }
}
