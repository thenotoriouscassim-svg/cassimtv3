class SystemStats {
  final double cpuPercent;
  final double ramUsedGb;
  final double ramTotalGb;
  final double ramPercent;
  final double storageUsedGb;
  final double storageTotalGb;
  final double storagePercent;
  final double? cpuTemp;
  final double? batteryPercent;
  final String networkStatus;
  final String platform;
  final int uptimeSeconds;

  const SystemStats({
    required this.cpuPercent,
    required this.ramUsedGb,
    required this.ramTotalGb,
    required this.ramPercent,
    required this.storageUsedGb,
    required this.storageTotalGb,
    required this.storagePercent,
    this.cpuTemp,
    this.batteryPercent,
    required this.networkStatus,
    required this.platform,
    required this.uptimeSeconds,
  });

  factory SystemStats.empty() => const SystemStats(
    cpuPercent: 0,
    ramUsedGb: 0,
    ramTotalGb: 0,
    ramPercent: 0,
    storageUsedGb: 0,
    storageTotalGb: 0,
    storagePercent: 0,
    networkStatus: 'unknown',
    platform: 'unknown',
    uptimeSeconds: 0,
  );

  factory SystemStats.fromJson(Map<String, dynamic> json) => SystemStats(
    cpuPercent:      (json['cpu_percent']       as num?)?.toDouble() ?? 0,
    ramUsedGb:       (json['ram_used_gb']        as num?)?.toDouble() ?? 0,
    ramTotalGb:      (json['ram_total_gb']       as num?)?.toDouble() ?? 0,
    ramPercent:      (json['ram_percent']        as num?)?.toDouble() ?? 0,
    storageUsedGb:   (json['storage_used_gb']   as num?)?.toDouble() ?? 0,
    storageTotalGb:  (json['storage_total_gb']  as num?)?.toDouble() ?? 0,
    storagePercent:  (json['storage_percent']   as num?)?.toDouble() ?? 0,
    cpuTemp:         (json['cpu_temp']           as num?)?.toDouble(),
    batteryPercent:  (json['battery_percent']   as num?)?.toDouble(),
    networkStatus:   json['network_status']     as String? ?? 'unknown',
    platform:        json['platform']           as String? ?? 'unknown',
    uptimeSeconds:   json['uptime_seconds']     as int?    ?? 0,
  );

  String get ramDisplay => '${ramUsedGb.toStringAsFixed(1)} / ${ramTotalGb.toStringAsFixed(1)} GB';
  String get storageDisplay => '${storageUsedGb.toStringAsFixed(1)} / ${storageTotalGb.toStringAsFixed(1)} GB';
  String get uptimeDisplay {
    final h = uptimeSeconds ~/ 3600;
    final m = (uptimeSeconds % 3600) ~/ 60;
    return '${h}h ${m}m';
  }
}
