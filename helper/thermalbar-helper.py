#!/usr/bin/env python3

import json
import os
import re
import subprocess
import tempfile
from datetime import datetime, timezone

STATUS_DIR = os.environ.get("THERMALBAR_STATUS_DIR", "/var/tmp/thermalbar")
STATUS_PATH = os.path.join(STATUS_DIR, "status.json")
SMC_READER_PATH = os.environ.get(
    "THERMALBAR_SMC_READER",
    "/Library/Application Support/ThermalBar/ThermalBarSMC",
)


def run(command, timeout):
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=False,
    )


def battery_metrics():
    result = run(["/usr/sbin/ioreg", "-r", "-n", "AppleSmartBattery", "-d", "1"], 5)
    text = result.stdout

    def scaled_int(name, scale):
        match = re.search(rf'"{re.escape(name)}"\s*=\s*(-?\d+)', text)
        if not match:
            return None
        return round(int(match.group(1)) / scale, 2)

    return {
        "batteryTemperatureC": scaled_int("Temperature", 100),
        "virtualTemperatureC": scaled_int("VirtualTemperature", 100),
        "systemPowerW": scaled_int("SystemPowerIn", 1000),
    }


def previous_status():
    try:
        with open(STATUS_PATH, "r") as status_file:
            return json.load(status_file)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def default_network_interface():
    result = run(["/sbin/route", "-n", "get", "default"], 3)
    if result.returncode != 0:
        return None

    match = re.search(r"^\s*interface:\s*(\S+)", result.stdout, re.MULTILINE)
    return match.group(1) if match else None


def network_counters():
    preferred = default_network_interface()
    result = run(["/usr/sbin/netstat", "-ibn"], 5)
    rows = []

    for line in result.stdout.splitlines()[1:]:
        columns = line.split()
        if len(columns) < 11 or not columns[2].startswith("<Link#"):
            continue

        name = columns[0].rstrip("*")
        if name == "lo0" or name.startswith(("awdl", "llw", "bridge")):
            continue

        try:
            rows.append(
                {
                    "interface": name,
                    "rxBytes": int(columns[6]),
                    "txBytes": int(columns[9]),
                }
            )
        except ValueError:
            continue

    if preferred:
        for row in rows:
            if row["interface"] == preferred:
                return row

    active_rows = [row for row in rows if row["rxBytes"] > 0 or row["txBytes"] > 0]
    if not active_rows:
        return {"interface": preferred, "rxBytes": None, "txBytes": None}

    # Prefer the busiest remaining interface as a fallback when no default route is available.
    return max(active_rows, key=lambda row: row["rxBytes"] + row["txBytes"])


def network_metrics(previous):
    counters = network_counters()
    current_time = datetime.now(timezone.utc)
    rx_bytes = counters.get("rxBytes")
    tx_bytes = counters.get("txBytes")

    metrics = {
        "networkInterface": counters.get("interface"),
        "networkRxBytes": rx_bytes,
        "networkTxBytes": tx_bytes,
        "networkDownloadBps": None,
        "networkUploadBps": None,
    }

    if not previous or rx_bytes is None or tx_bytes is None:
        return metrics

    if previous.get("networkInterface") != counters.get("interface"):
        return metrics

    previous_rx = previous.get("networkRxBytes")
    previous_tx = previous.get("networkTxBytes")
    previous_timestamp = previous.get("timestamp")
    if not isinstance(previous_rx, int) or not isinstance(previous_tx, int) or not previous_timestamp:
        return metrics

    try:
        previous_time = datetime.fromisoformat(previous_timestamp.replace("Z", "+00:00"))
    except ValueError:
        return metrics

    elapsed = (current_time - previous_time).total_seconds()
    if elapsed <= 0 or rx_bytes < previous_rx or tx_bytes < previous_tx:
        return metrics

    metrics["networkDownloadBps"] = round((rx_bytes - previous_rx) / elapsed, 1)
    metrics["networkUploadBps"] = round((tx_bytes - previous_tx) / elapsed, 1)
    return metrics


def parse_power_line(text, label):
    patterns = [
        rf"{label}.*?Power[^:\n]*:\s*([0-9.]+)\s*(mW|W)",
        rf"{label}[^0-9\n]*([0-9.]+)\s*(mW|W)",
    ]
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            value = float(match.group(1))
            unit = match.group(2).lower()
            return round(value / 1000, 2) if unit == "mw" else round(value, 2)
    return None


def powermetrics_metrics():
    result = run(
        [
            "/usr/bin/powermetrics",
            "--samplers",
            "thermal,cpu_power,gpu_power,ane_power,battery",
            "-n",
            "1",
            "-i",
            "1000",
        ],
        8,
    )
    combined = "\n".join(part for part in [result.stdout, result.stderr] if part)
    if result.returncode != 0:
        return {
            "thermalPressure": None,
            "cpuPowerW": None,
            "gpuPowerW": None,
            "anePowerW": None,
            "rawSummary": combined.strip()[-4000:],
            "error": combined.strip() or f"powermetrics exited {result.returncode}",
        }

    pressure = None
    for pattern in [
        r"Thermal pressure:\s*([^\n]+)",
        r"thermal pressure.*?:\s*([^\n]+)",
    ]:
        match = re.search(pattern, result.stdout, re.IGNORECASE)
        if match:
            pressure = match.group(1).strip()
            break

    return {
        "thermalPressure": pressure,
        "fanRPM": fan_rpm(result.stdout),
        "cpuPowerW": parse_power_line(result.stdout, "CPU"),
        "gpuPowerW": parse_power_line(result.stdout, "GPU"),
        "anePowerW": parse_power_line(result.stdout, "ANE"),
        "rawSummary": result.stdout.strip()[-4000:],
        "error": None,
    }


def fan_rpm(text):
    patterns = [
        r"fan[^:\n]*:\s*([0-9.]+)\s*rpm",
        r"fan[^0-9\n]*([0-9.]+)\s*rpm",
        r"([0-9.]+)\s*rpm",
    ]
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return round(float(match.group(1)), 0)
    return None


def smc_fan_metrics():
    if not os.path.exists(SMC_READER_PATH):
        return {"fanRPM": None, "fanCount": None, "fanReadout": None, "fanError": "SMC reader not installed"}
    result = run([SMC_READER_PATH], 5)
    text = result.stdout.strip()
    try:
        payload = json.loads(text) if text else {}
    except json.JSONDecodeError as error:
        return {"fanRPM": None, "fanCount": None, "fanReadout": None, "fanError": f"SMC reader JSON error: {error}"}

    fans = payload.get("fans") or []
    rpms = [fan.get("rpm") for fan in fans if isinstance(fan.get("rpm"), (int, float))]
    return {
        "fanRPM": round(max(rpms), 0) if rpms else None,
        "fanCount": payload.get("fanCount"),
        "fanReadout": fans,
        "fanError": payload.get("error") or (result.stderr.strip() if result.returncode != 0 else None),
    }


def write_status(payload):
    os.makedirs(STATUS_DIR, mode=0o755, exist_ok=True)
    fd, temp_path = tempfile.mkstemp(prefix="status.", suffix=".json", dir=STATUS_DIR)
    with os.fdopen(fd, "w") as temp_file:
        json.dump(payload, temp_file, ensure_ascii=False, indent=2)
        temp_file.write("\n")
    os.chmod(temp_path, 0o644)
    os.replace(temp_path, STATUS_PATH)


def main():
    previous = previous_status()
    payload = {
        "schemaVersion": 1,
        "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "source": "thermalbar-helper",
        "thermalPressure": None,
        "batteryTemperatureC": None,
        "virtualTemperatureC": None,
        "systemPowerW": None,
        "fanRPM": None,
        "fanCount": None,
        "fanReadout": None,
        "fanError": None,
        "networkInterface": None,
        "networkRxBytes": None,
        "networkTxBytes": None,
        "networkDownloadBps": None,
        "networkUploadBps": None,
        "cpuPowerW": None,
        "gpuPowerW": None,
        "anePowerW": None,
        "rawSummary": None,
        "error": None,
    }

    try:
        payload.update(battery_metrics())
        payload.update(network_metrics(previous))
        payload.update(powermetrics_metrics())
        smc_fans = smc_fan_metrics()
        if smc_fans.get("fanRPM") is not None or payload.get("fanRPM") is None:
            payload.update(smc_fans)
    except Exception as error:
        payload["error"] = str(error)

    write_status(payload)


if __name__ == "__main__":
    main()
