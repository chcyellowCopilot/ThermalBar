import Foundation

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpuUsage
    case cpuTemperature
    case batteryTemperature
    case virtualTemperature
    case fanSpeed
    case downloadSpeed
    case uploadSpeed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuUsage:
            "CPU 使用率"
        case .cpuTemperature:
            "CPU 温度"
        case .batteryTemperature:
            "电池温度"
        case .virtualTemperature:
            "虚拟温度"
        case .fanSpeed:
            "风扇转速"
        case .downloadSpeed:
            "下载速度"
        case .uploadSpeed:
            "上传速度"
        }
    }

    var statusBarSlotWidth: Double {
        switch self {
        case .cpuUsage:
            46
        case .cpuTemperature:
            30
        case .batteryTemperature, .virtualTemperature:
            30
        case .fanSpeed:
            62
        case .downloadSpeed, .uploadSpeed:
            46
        }
    }

    static let defaultSelection: [MenuBarMetric] = [
        .batteryTemperature,
    ]

    func isAvailable(for status: ThermalStatus?) -> Bool {
        switch self {
        case .batteryTemperature, .virtualTemperature:
            status?.hasBattery != false
        case .cpuUsage, .cpuTemperature, .fanSpeed, .downloadSpeed, .uploadSpeed:
            true
        }
    }
}
