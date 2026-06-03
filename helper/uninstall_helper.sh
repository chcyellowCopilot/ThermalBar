#!/usr/bin/env bash
set -euo pipefail

PLIST="/Library/LaunchDaemons/com.local.thermalbar.helper.plist"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "uninstall_helper.sh must run as root" >&2
  exit 1
fi

launchctl bootout system/com.local.thermalbar.helper >/dev/null 2>&1 || true
rm -f "$PLIST"
rm -rf "/Library/Application Support/ThermalBar"
rm -rf /var/tmp/thermalbar
