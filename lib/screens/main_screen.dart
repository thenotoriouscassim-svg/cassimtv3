import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../utils/constants.dart';
import '../widgets/jarvis_core_widget.dart';
import '../widgets/conversation_panel.dart';
import '../widgets/stats_panel.dart';
import '../widgets/input_bar.dart';
import '../widgets/status_bar_widget.dart';
import 'settings_screen.dart';
import 'memory_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late AnimationController _bootController;
  late Animation<double> _bootFade;
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    _bootController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _bootFade = CurvedAnimation(parent: _bootController, curve: Curves.easeIn);
    _boot();
  }

  Future<void> _boot() async {
    await Future.delayed(const Duration(milliseconds: 300));
    _bootController.forward();
    await Future.delayed(const Duration(milliseconds: 2500));
    setState(() => _booted = true);
  }

  @override
  void dispose() {
    _bootController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTV = size.width > 900;

    return Scaffold(
      backgroundColor: JarvisColors.background,
      body: FadeTransition(
        opacity: _bootFade,
        child: _booted
            ? (isTV ? _buildTVLayout(context) : _buildMobileLayout(context))
            : _buildBootScreen(),
      ),
    );
  }

  // ─── Boot Screen ──────────────────────────────────────────────────────

  Widget _buildBootScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _glowText('JARVIS AI', 32, JarvisColors.cyan),
          const SizedBox(height: 8),
          _glowText('by CassimTV', 14, JarvisColors.textSecondary),
          const SizedBox(height: 48),
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: JarvisColors.border,
              color: JarvisColors.cyan,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'INITIALIZING SYSTEMS...',
            style: TextStyle(
              color: JarvisColors.textSecondary,
              fontSize: 10,
              letterSpacing: 3,
              fontFamily: 'Orbitron',
            ),
          ),
        ],
      ),
    );
  }

  // ─── TV Layout ───────────────────────────────────────────────────────

  Widget _buildTVLayout(BuildContext context) {
    return Column(
      children: [
        const StatusBarWidget(),
        Expanded(
          child: Row(
            children: [
              // Left: Stats panel
              SizedBox(
                width: 220,
                child: const StatsPanel(),
              ),
              const VerticalDivider(color: JarvisColors.border, width: 1),

              // Center: JARVIS core + conversation
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    const Expanded(flex: 2, child: JarvisCoreWidget()),
                    const Divider(color: JarvisColors.border, height: 1),
                    const Expanded(flex: 3, child: ConversationPanel()),
                    const InputBar(),
                  ],
                ),
              ),

              const VerticalDivider(color: JarvisColors.border, width: 1),

              // Right: Quick actions
              SizedBox(
                width: 180,
                child: _buildQuickActions(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Mobile Layout ───────────────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context) {
    return Column(
      children: [
        const StatusBarWidget(),
        const SizedBox(height: 8),
        const SizedBox(height: 200, child: JarvisCoreWidget()),
        const StatsPanel(),
        const Expanded(child: ConversationPanel()),
        const InputBar(),
      ],
    );
  }

  // ─── Quick Actions ───────────────────────────────────────────────────

  Widget _buildQuickActions(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    return Container(
      color: JarvisColors.surface,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _glowText('QUICK ACCESS', 10, JarvisColors.textSecondary),
          const SizedBox(height: 12),
          _quickBtn(context, 'RAM STATUS',   Icons.memory,        () => jarvis.executeCommand('ram_status')),
          _quickBtn(context, 'CPU STATUS',   Icons.developer_board,() => jarvis.executeCommand('cpu_status')),
          _quickBtn(context, 'STORAGE',      Icons.storage,       () => jarvis.executeCommand('storage_status')),
          _quickBtn(context, 'NETWORK',      Icons.wifi,          () => jarvis.executeCommand('network_status')),
          _quickBtn(context, 'BATTERY',      Icons.battery_full,  () => jarvis.executeCommand('battery_status')),
          const Divider(color: JarvisColors.border),
          _quickBtn(context, 'MEMORY',       Icons.psychology,    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryScreen()))),
          _quickBtn(context, 'SETTINGS',     Icons.settings,      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          _quickBtn(context, 'CLEAR CHAT',   Icons.clear_all,     () => jarvis.clearConversation()),
          const Spacer(),
          Center(
            child: Text(
              'JARVIS AI v1.0\nby CassimTV',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: JarvisColors.textDim,
                fontSize: 9,
                height: 1.6,
                letterSpacing: 1,
                fontFamily: 'Orbitron',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickBtn(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: JarvisColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(icon, color: JarvisColors.cyan, size: 14),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: JarvisColors.textPrimary,
                    fontSize: 10,
                    letterSpacing: 1,
                    fontFamily: 'Orbitron',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _glowText(String text, double size, Color color) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: size,
        fontFamily: 'Orbitron',
        fontWeight: FontWeight.bold,
        letterSpacing: 3,
        shadows: [Shadow(color: color.withOpacity(0.8), blurRadius: 20)],
      ),
    );
  }
}
