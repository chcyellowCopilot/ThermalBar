# ThermalBar

ThermalBar is a personal macOS menu bar monitor for Apple Silicon Macs. It reads thermal and power telemetry from a root LaunchDaemon helper and displays the latest status in a SwiftUI `MenuBarExtra`.

## Build and Run

```bash
./script/build_and_run.sh
```

## Helper

Use the menu bar item to install or uninstall the helper. macOS will ask for administrator authorization. The app does not store sudo passwords.

The helper writes:

```text
/var/tmp/thermalbar/status.json
```

It installs:

```text
/Library/LaunchDaemons/com.local.thermalbar.helper.plist
/Library/Application Support/ThermalBar/thermalbar-helper.py
```
