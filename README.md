# ThermalBar
# ByCodex

ThermalBar is a personal macOS menu bar monitor for Apple Silicon Macs. It reads local temperature, fan speed, network speed, and CPU usage telemetry directly from the app bundle and displays the latest status in a SwiftUI `MenuBarExtra`.

## Build and Run

```bash
./script/build_and_run.sh
```

## Telemetry

ThermalBar does not require a privileged helper or LaunchDaemon.

Current data sources:

- CPU temperature and fan speed: bundled `ThermalBarSMC`
- Battery and virtual temperature: `ioreg`
- CPU usage: host processor tick deltas
- Network speed: local network counters
