import Foundation

struct LocalSensorReader {
    func readStatus() -> ThermalStatus {
        let battery = batteryMetrics()
        let smc = smcMetrics()
        let error = smc.error

        return ThermalStatus(
            schemaVersion: 1,
            timestamp: Date(),
            source: "thermalbar-local",
            hasBattery: battery.hasBattery,
            thermalPressure: nil,
            batteryTemperatureC: battery.batteryTemperatureC,
            virtualTemperatureC: battery.virtualTemperatureC,
            cpuTemperatureC: smc.cpuTemperatureC,
            systemPowerW: nil,
            fanRPM: smc.fanRPM,
            networkInterface: nil,
            networkDownloadBps: nil,
            networkUploadBps: nil,
            cpuPowerW: nil,
            gpuPowerW: nil,
            anePowerW: nil,
            rawSummary: smc.rawSummary,
            error: error
        )
    }

    private func batteryMetrics() -> (hasBattery: Bool, batteryTemperatureC: Double?, virtualTemperatureC: Double?) {
        let result = run("/usr/sbin/ioreg", arguments: ["-r", "-n", "AppleSmartBattery", "-d", "1"], timeout: 5)
        let hasBattery = !result.output.contains("\"BatteryInstalled\" = No")
            && (
                result.output.contains("\"BatteryInstalled\" = Yes")
                || result.output.contains("\"Temperature\"")
                || result.output.contains("\"VirtualTemperature\"")
            )
        return (
            hasBattery,
            scaledInt(named: "Temperature", in: result.output, scale: 100),
            scaledInt(named: "VirtualTemperature", in: result.output, scale: 100)
        )
    }

    private func smcMetrics() -> (cpuTemperatureC: Double?, fanRPM: Double?, rawSummary: String?, error: String?) {
        guard let smcPath = smcReaderPath() else {
            return (nil, nil, nil, "ThermalBarSMC not found")
        }

        let result = run(smcPath, arguments: [], timeout: 5)
        guard let data = result.output.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let message = [result.output, result.errorOutput]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return (nil, nil, nil, message.isEmpty ? "ThermalBarSMC returned invalid JSON" : message)
        }

        let fans = payload["fans"] as? [[String: Any]] ?? []
        let rpms = fans.compactMap { $0["rpm"] as? Double }
        let error = payload["error"] as? String
        return (
            payload["cpuTemperatureC"] as? Double,
            rpms.max().map { round($0) },
            result.output,
            error?.isEmpty == false ? error : nil
        )
    }

    private func smcReaderPath() -> String? {
        if let bundledPath = Bundle.main.path(forResource: "ThermalBarSMC", ofType: nil) {
            return bundledPath
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let siblingURL = executableURL.deletingLastPathComponent().appendingPathComponent("ThermalBarSMC")
        if FileManager.default.isExecutableFile(atPath: siblingURL.path) {
            return siblingURL.path
        }

        return nil
    }

    private func scaledInt(named name: String, in text: String, scale: Double) -> Double? {
        let pattern = #"""# + NSRegularExpression.escapedPattern(for: name) + #""\s*=\s*(-?\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]) else {
            return nil
        }
        return (value / scale * 100).rounded() / 100
    }

    private func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> (output: String, errorOutput: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return ("", error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (output.trimmingCharacters(in: .whitespacesAndNewlines), errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
