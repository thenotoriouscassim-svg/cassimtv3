"""
JARVIS Action Engine
Executes real system commands using psutil (free, cross-platform).
All readings are real. Protocol 001 enforced — no fake data.
"""

import platform
import subprocess
import psutil
import time


class ActionEngine:
    async def execute(self, command: str) -> dict:
        handlers = {
            "ram_status":     self._ram,
            "cpu_status":     self._cpu,
            "storage_status": self._storage,
            "network_status": self._network,
            "battery_status": self._battery,
            "processes":      self._processes,
            "uptime":         self._uptime,
        }
        handler = handlers.get(command)
        if handler:
            return handler()
        return {"error": f"Unknown command: {command}"}

    # ─── Real System Data ────────────────────────────────────────────────

    def _ram(self) -> dict:
        m = psutil.virtual_memory()
        s = psutil.swap_memory()
        return {
            "total_gb":    round(m.total / 1e9, 2),
            "used_gb":     round(m.used  / 1e9, 2),
            "available_gb":round(m.available / 1e9, 2),
            "percent":     m.percent,
            "swap_used_gb":round(s.used / 1e9, 2),
            "swap_total_gb":round(s.total / 1e9, 2),
        }

    def _cpu(self) -> dict:
        cpu_pct   = psutil.cpu_percent(interval=1, percpu=False)
        per_core  = psutil.cpu_percent(interval=0.1, percpu=True)
        cpu_freq  = psutil.cpu_freq()
        cpu_count = psutil.cpu_count(logical=True)

        temp = None
        try:
            temps = psutil.sensors_temperatures()
            for key in ("coretemp", "cpu_thermal", "cpu-thermal", "k10temp"):
                if key in temps and temps[key]:
                    temp = round(temps[key][0].current, 1)
                    break
        except Exception:
            pass

        return {
            "usage_percent":  cpu_pct,
            "per_core":       per_core,
            "cores":          cpu_count,
            "freq_mhz":       round(cpu_freq.current, 0) if cpu_freq else None,
            "temp_celsius":   temp,
            "platform":       platform.processor(),
        }

    def _storage(self) -> dict:
        partitions = []
        for p in psutil.disk_partitions():
            try:
                usage = psutil.disk_usage(p.mountpoint)
                partitions.append({
                    "device":     p.device,
                    "mountpoint": p.mountpoint,
                    "total_gb":   round(usage.total / 1e9, 2),
                    "used_gb":    round(usage.used  / 1e9, 2),
                    "free_gb":    round(usage.free  / 1e9, 2),
                    "percent":    usage.percent,
                })
            except PermissionError:
                pass
        return {"partitions": partitions}

    def _network(self) -> dict:
        stats    = psutil.net_if_stats()
        addrs    = psutil.net_if_addrs()
        io       = psutil.net_io_counters()
        ifaces   = []
        for name, stat in stats.items():
            addr_list = []
            for a in addrs.get(name, []):
                if a.family.name in ("AF_INET", "AF_INET6"):
                    addr_list.append(a.address)
            ifaces.append({
                "name":    name,
                "up":      stat.isup,
                "speed":   stat.speed,
                "addresses": addr_list,
            })
        return {
            "interfaces":    ifaces,
            "bytes_sent_mb": round(io.bytes_sent / 1e6, 2),
            "bytes_recv_mb": round(io.bytes_recv / 1e6, 2),
        }

    def _battery(self) -> dict:
        try:
            b = psutil.sensors_battery()
            if b is None:
                return {"available": False}
            return {
                "available":   True,
                "percent":     round(b.percent, 1),
                "plugged_in":  b.power_plugged,
                "time_left_min": round(b.secsleft / 60) if b.secsleft > 0 else None,
            }
        except Exception:
            return {"available": False}

    def _processes(self) -> dict:
        procs = []
        for p in sorted(psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent']),
                         key=lambda x: x.info['memory_percent'] or 0, reverse=True)[:10]:
            procs.append({
                "pid":    p.info['pid'],
                "name":   p.info['name'],
                "cpu":    round(p.info['cpu_percent'] or 0, 1),
                "mem":    round(p.info['memory_percent'] or 0, 1),
            })
        return {"top_processes": procs}

    def _uptime(self) -> dict:
        secs  = int(time.time() - psutil.boot_time())
        hours = secs // 3600
        mins  = (secs % 3600) // 60
        return {"uptime_seconds": secs, "hours": hours, "minutes": mins}
