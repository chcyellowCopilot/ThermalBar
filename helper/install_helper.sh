#!/usr/bin/env bash
set -euo pipefail

APP_SUPPORT="/Library/Application Support/ThermalBar"
HELPER="$APP_SUPPORT/thermalbar-helper.py"
SMC_READER="$APP_SUPPORT/ThermalBarSMC"
PLIST="/Library/LaunchDaemons/com.local.thermalbar.helper.plist"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "install_helper.sh must run as root" >&2
  exit 1
fi

mkdir -p "$APP_SUPPORT" /var/tmp/thermalbar
cp "$SOURCE_DIR/thermalbar-helper.py" "$HELPER"
if [[ -f "$SOURCE_DIR/ThermalBarSMC" ]]; then
  cp "$SOURCE_DIR/ThermalBarSMC" "$SMC_READER"
  chmod 755 "$SMC_READER"
  chown root:wheel "$SMC_READER"
fi
chmod 755 "$HELPER"
chown root:wheel "$HELPER"
chmod 755 "$APP_SUPPORT"
chown root:wheel "$APP_SUPPORT"
chmod 755 /var/tmp/thermalbar

cat >"$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.thermalbar.helper</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>$HELPER</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>3</integer>
  <key>StandardOutPath</key>
  <string>/var/tmp/thermalbar/helper.out.log</string>
  <key>StandardErrorPath</key>
  <string>/var/tmp/thermalbar/helper.err.log</string>
</dict>
</plist>
PLIST

chmod 644 "$PLIST"
chown root:wheel "$PLIST"

launchctl bootout system/com.local.thermalbar.helper >/dev/null 2>&1 || true
launchctl bootstrap system "$PLIST"
launchctl kickstart -k system/com.local.thermalbar.helper
