import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/jarvis_service.dart';
import '../utils/constants.dart';

class StatsPanel extends StatelessWidget {
  const StatsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final jarvis = context.watch<JarvisService>();
    final stats  = jarvis.systemStats;
    final size   = MediaQuery.of(context).size;
    final isTV   = size.width > 900;

    if (isTV) {
      return _buildVertical(stats, jarvis.isConnected);
    } else {
      return _buildHorizontal(stats, jarvis.isConnected);
    }
  }

  Widget _buildVertical(stats, bool connected) {
    return Container(
      color: JarvisColors.surface,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('SYSTEM STATUS'),
          const SizedBox(height: 10),
          _connectionDot(connected),
          const SizedBox(height: 14),
          _StatGauge(label: 'CPU', value: stats.cpuPercent, unit: '%', color: JarvisColors.electricBlue),
          const SizedBox(height: 10),
          _StatGauge(label: 'RAM', value: stats.ramPercent, unit: '%', color: JarvisColors.cyan, sublabel: stats.ramDisplay),
          const SizedBox(height: 10),
          _StatGauge(label: 'STORAGE', value: stats.storagePercent, unit: '%', color: JarvisColors.neonBlue, sublabel: stats.storageDisplay),
          if (stats.cpuTemp != null) ...[
            const SizedBox(height: 10),
            _StatGauge(label: 'TEMP', value: stats.cpuTemp!, unit: '°C',
              color: stats.cpuTemp! > 70 ? JarvisColors.red : JarvisColors.green,
              maxValue: 100),
          ],
          if (stats.batteryPercent != null) ...[
            const SizedBox(height: 10),
            _StatGauge(label: 'BATTERY', value: stats.batteryPercent!, unit: '%',
              color: stats.batteryPercent! < 20 ? JarvisColors.red : JarvisColors.green),
          ],
          const Divider(color: JarvisColors.border),
          _infoRow('PLATFORM', stats.platform.toUpperCase()),
          const SizedBox(height: 4),
          _infoRow('UPTIME', stats.uptimeDisplay),
          _infoRow('NETWORK', stats.networkStatus.toUpperCase()),
        ],
      ),
    );
  }

  Widget _buildHorizontal(stats, bool connected) {
    return Container(
      height: 80,
      color: JarvisColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _MiniStat(label: 'CPU', value: '${stats.cpuPercent.toStringAsFixed(0)}%', color: JarvisColors.electricBlue)),
          Expanded(child: _MiniStat(label: 'RAM', value: '${stats.ramPercent.toStringAsFixed(0)}%', color: JarvisColors.cyan)),
          Expanded(child: _MiniStat(label: 'STORAGE', value: '${stats.storagePercent.toStringAsFixed(0)}%', color: JarvisColors.neonBlue)),
          if (stats.batteryPercent != null)
            Expanded(child: _MiniStat(label: 'BATTERY', value: '${stats.batteryPercent!.toStringAsFixed(0)}%',
              color: stats.batteryPercent! < 20 ? JarvisColors.red : JarvisColors.green)),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: JarvisColors.textSecondary,
      fontSize: 9,
      letterSpacing: 2,
      fontFamily: 'Orbitron',
    ),
  );

  Widget _connectionDot(bool connected) => Row(
    children: [
      Container(
        width: 6, height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? JarvisColors.green : JarvisColors.red,
          boxShadow: [BoxShadow(color: connected ? JarvisColors.green : JarvisColors.red, blurRadius: 6)],
        ),
      ),
      const SizedBox(width: 6),
      Text(
        connected ? 'BACKEND ONLINE' : 'BACKEND OFFLINE',
        style: TextStyle(
          color: connected ? JarvisColors.green : JarvisColors.red,
          fontSize: 9, letterSpacing: 1, fontFamily: 'Orbitron',
        ),
      ),
    ],
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: JarvisColors.textDim, fontSize: 8, fontFamily: 'Orbitron')),
        Text(value, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 8, fontFamily: 'Orbitron')),
      ],
    ),
  );
}

class _StatGauge extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;
  final String? sublabel;
  final double maxValue;

  const _StatGauge({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    this.sublabel,
    this.maxValue = 100,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (value / maxValue).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: JarvisColors.textSecondary, fontSize: 9, letterSpacing: 1, fontFamily: 'Orbitron')),
            Text('${value.toStringAsFixed(1)}$unit',
              style: TextStyle(color: color, fontSize: 10, fontFamily: 'Orbitron',
                shadows: [Shadow(color: color.withOpacity(0.6), blurRadius: 6)])),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: JarvisColors.border,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 3,
          ),
        ),
        if (sublabel != null) ...[
          const SizedBox(height: 2),
          Text(sublabel!, style: const TextStyle(color: JarvisColors.textDim, fontSize: 8, fontFamily: 'Orbitron')),
        ],
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold,
          fontFamily: 'Orbitron', shadows: [Shadow(color: color.withOpacity(0.6), blurRadius: 8)])),
        Text(label, style: const TextStyle(color: JarvisColors.textDim, fontSize: 8, letterSpacing: 1, fontFamily: 'Orbitron')),
      ],
    );
  }
}
