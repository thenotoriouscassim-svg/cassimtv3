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
      height: 56,
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
