import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class ThermalStatusStore {
    var status: ThermalStatus?
    var helperState: HelperState = .notInstalled
    var lastReadError: String?
    var isRefreshing = false
    var networkInterface: String?
    var networkDownloadBps: Double?
    var networkUploadBps: Double?
    var cpuUsagePercent: Double?
    var menuBarMetricIDs: [String]
    var menuBarTitle = "温度监控"
    var statusBarTitle = "温度监控"
    var statusBarWidth: Double = 96

    @ObservationIgnored
    @UserDefaultsBacked(key: "sampleIntervalSeconds", defaultValue: 3)
    var sampleIntervalSeconds: Int

    @ObservationIgnored
    private let menuBarMetricIDsKey = "menuBarMetricIDs"

    @ObservationIgnored
    private let reader = LocalSensorReader()

    @ObservationIgnored
    private let networkSampler = NetworkSpeedSampler()

    @ObservationIgnored
    private let cpuSampler = CPUUsageSampler()

    @ObservationIgnored
    private var statusTimer: Timer?

    @ObservationIgnored
    private var networkTimer: Timer?

    @ObservationIgnored
    private var cpuTimer: Timer?

    @ObservationIgnored
    private var wakeObserver: NSObjectProtocol?

    init() {
        menuBarMetricIDs = UserDefaults.standard.stringArray(forKey: menuBarMetricIDsKey)
            ?? MenuBarMetric.defaultSelection.map(\.rawValue)
        refresh()
        updateNetworkSpeed()
        updateCPUUsage()
        startStatusTimer()
        startNetworkTimer()
        startCPUTimer()
        observeWake()
    }

    var selectedMenuBarMetrics: [MenuBarMetric] {
        menuBarMetricIDs.compactMap(MenuBarMetric.init(rawValue:))
    }

    func isMenuBarMetricSelected(_ metric: MenuBarMetric) -> Bool {
        selectedMenuBarMetrics.contains(metric)
    }

    func setMenuBarMetric(_ metric: MenuBarMetric, enabled: Bool) {
        var metrics = selectedMenuBarMetrics
        if enabled {
            guard !metrics.contains(metric) else {
                return
            }
            metrics.append(metric)
        } else {
            metrics.removeAll { $0 == metric }
        }
        menuBarMetricIDs = metrics.map(\.rawValue)
        UserDefaults.standard.set(menuBarMetricIDs, forKey: menuBarMetricIDsKey)
        rebuildMenuBarTitle()
    }

    var menuBarSymbol: String {
        if case .failed = helperState {
            return "exclamationmark.triangle"
        }
        if helperState == .stale {
            return "clock.badge.exclamationmark"
        }
        return "thermometer.medium"
    }

    func setSampleInterval(_ value: Int) {
        sampleIntervalSeconds = value
        startStatusTimer()
    }

    func menuBarValue(for metric: MenuBarMetric) -> String? {
        switch metric {
        case .cpuUsage:
            return valueOrNil(Formatters.percent(cpuUsagePercent)).map { "CPU \($0)" }
        case .cpuTemperature:
            return valueOrNil(Formatters.temperature(status?.cpuTemperatureC)).map { "CPU \($0)" }
        case .batteryTemperature:
            return valueOrNil(Formatters.temperature(status?.batteryTemperatureC))
        case .virtualTemperature:
            return valueOrNil(Formatters.temperature(status?.virtualTemperatureC))
        case .fanSpeed:
            return valueOrNil(Formatters.fanSpeed(status?.fanRPM))
        case .downloadSpeed:
            return valueOrNil(Formatters.networkSpeed(networkDownloadBps)).map { "↓\($0)" }
        case .uploadSpeed:
            return valueOrNil(Formatters.networkSpeed(networkUploadBps)).map { "↑\($0)" }
        }
    }

    func statusBarValue(for metric: MenuBarMetric) -> String? {
        switch metric {
        case .cpuUsage:
            return valueOrNil(Formatters.percent(cpuUsagePercent)).flatMap { fixed("CPU \($0)", width: 7) }
        case .cpuTemperature:
            return valueOrNil(Formatters.temperature(status?.cpuTemperatureC)).flatMap { fixed("CPU \($0)", width: 7) }
        case .batteryTemperature:
            return fixed(Formatters.temperature(status?.batteryTemperatureC), width: 4)
        case .virtualTemperature:
            return fixed(Formatters.temperature(status?.virtualTemperatureC), width: 4)
        case .fanSpeed:
            return fixed(Formatters.fanSpeed(status?.fanRPM), width: 8)
        case .downloadSpeed:
            return Formatters.statusBarNetworkSpeed(networkDownloadBps)
        case .uploadSpeed:
            return Formatters.statusBarNetworkSpeedUp(networkUploadBps)
        }
    }

    private func valueOrNil(_ value: String) -> String? {
        value == "—" || value == "系统未公开" ? nil : value
    }

    private func fixed(_ value: String, width: Int) -> String? {
        guard let value = valueOrNil(value) else {
            return nil
        }

        let count = value.count
        guard count < width else {
            return value
        }

        return String(repeating: "\u{2007}", count: width - count) + value
    }

    private func rebuildMenuBarTitle() {
        if status?.isError == true {
            menuBarTitle = "监控错误"
            statusBarTitle = "监控错误"
            statusBarWidth = 72
        } else {
            let values = selectedMenuBarMetrics.compactMap(menuBarValue)
            let statusBarValues = selectedMenuBarMetrics.compactMap(statusBarValue)
            menuBarTitle = values.isEmpty ? "温度监控" : values.joined(separator: " · ")
            statusBarTitle = statusBarValues.isEmpty ? "温度监控" : statusBarValues.joined(separator: "·")
            statusBarWidth = fixedStatusBarWidth(for: selectedMenuBarMetrics)
        }

        NotificationCenter.default.post(
            name: .menuBarTitleDidChange,
            object: self,
            userInfo: [
                "title": statusBarTitle,
                "symbol": menuBarSymbol,
                "width": statusBarWidth,
            ]
        )
    }

    private func fixedStatusBarWidth(for metrics: [MenuBarMetric]) -> Double {
        guard !metrics.isEmpty else {
            return 72
        }

        let separatorWidth = Double(max(metrics.count - 1, 0)) * 4
        let contentWidth = metrics.reduce(0) { $0 + $1.statusBarSlotWidth }
        return max(72, contentWidth + separatorWidth)
    }

    func refresh() {
        isRefreshing = true
        defer {
            isRefreshing = false
            rebuildMenuBarTitle()
        }

        let newStatus = reader.readStatus()
        status = newStatus
        lastReadError = nil
        if newStatus.error == "ThermalBarSMC not found" {
            helperState = .notInstalled
        } else if newStatus.isError {
            helperState = .failed(newStatus.error ?? "Unknown local reader error")
        } else {
            helperState = .running
        }
    }

    private func updateNetworkSpeed() {
        let sample = networkSampler.sample()
        networkInterface = sample.interface
        networkDownloadBps = sample.downloadBps
        networkUploadBps = sample.uploadBps
        rebuildMenuBarTitle()
    }

    private func startStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: Double(sampleIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        statusTimer?.tolerance = min(Double(sampleIntervalSeconds) * 0.2, 1.0)
    }

    private func startNetworkTimer() {
        networkTimer?.invalidate()
        networkTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateNetworkSpeed()
            }
        }
        networkTimer?.tolerance = 0.1
    }

    private func updateCPUUsage() {
        cpuUsagePercent = cpuSampler.sample().usagePercent
        rebuildMenuBarTitle()
    }

    private func startCPUTimer() {
        cpuTimer?.invalidate()
        cpuTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCPUUsage()
            }
        }
        cpuTimer?.tolerance = 0.1
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.networkSampler.reset()
                self?.cpuSampler.reset()
                self?.refresh()
                self?.updateNetworkSpeed()
                self?.updateCPUUsage()
            }
        }
    }
}
