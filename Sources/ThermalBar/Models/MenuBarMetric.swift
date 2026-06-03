import Foundation

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpuUsage
    case batteryTemperature
    case virtualTemperature
    case systemPower
    case fanSpeed
    case downloadSpeed
    case uploadSpeed
    case cpuPower
    case gpuPower
    case anePower
    case thermalPressure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuUsage:
            "CPU 使用率"
        case .batteryTemperature:
            "电池温度"
        case .virtualTemperature:
            "虚拟温度"
        case .systemPower:
            "系统功耗"
        case .fanSpeed:
            "风扇转速"
        case .downloadSpeed:
            "下载速度"
        case .uploadSpeed:
            "上传速度"
        case .cpuPower:
            "CPU 功耗"
        case .gpuPower:
            "GPU 功耗"
        case .anePower:
            "ANE 功耗"
        case .thermalPressure:
            "热压力"
        }
    }

    var statusBarSlotWidth: Double {
        switch self {
        case .cpuUsage:
            46
        case .batteryTemperature, .virtualTemperature:
            30
        case .systemPower:
            42
        case .fanSpeed:
            62
        case .downloadSpeed, .uploadSpeed:
            46
        case .cpuPower, .gpuPower, .anePower:
            58
        case .thermalPressure:
            58
        }
    }

    static let defaultSelection: [MenuBarMetric] = [
        .batteryTemperature,
        .systemPower,
    ]
}
