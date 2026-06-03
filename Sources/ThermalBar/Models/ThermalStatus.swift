import Foundation

struct ThermalStatus: Codable, Equatable {
    let schemaVersion: Int
    let timestamp: Date
    let source: String
    let thermalPressure: String?
    let batteryTemperatureC: Double?
    let virtualTemperatureC: Double?
    let systemPowerW: Double?
    let fanRPM: Double?
    let networkInterface: String?
    let networkDownloadBps: Double?
    let networkUploadBps: Double?
    let cpuPowerW: Double?
    let gpuPowerW: Double?
    let anePowerW: Double?
    let rawSummary: String?
    let error: String?

    var isError: Bool {
        if let error, !error.isEmpty {
            return true
        }
        return false
    }
}

enum HelperState: Equatable {
    case notInstalled
    case stale
    case running
    case failed(String)

    var title: String {
        switch self {
        case .notInstalled:
            "辅助服务未安装"
        case .stale:
            "数据已过期"
        case .running:
            "运行中"
        case .failed:
            "辅助服务错误"
        }
    }
}
