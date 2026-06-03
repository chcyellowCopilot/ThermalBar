import Foundation

enum Formatters {
    static func temperature(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°C"
    }

    static func power(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1fW", value)
    }

    static func fanSpeed(_ value: Double?) -> String {
        guard let value else { return "系统未公开" }
        return "\(Int(value.rounded())) RPM"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    static func networkSpeed(_ value: Double?) -> String {
        guard let value else { return "—" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var scaled = max(0, value)
        var unitIndex = 0
        while scaled >= 1024, unitIndex < units.count - 1 {
            scaled /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(scaled.rounded())) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", scaled, units[unitIndex])
    }

    static func compactNetworkSpeed(_ value: Double?) -> String {
        guard let value else { return "—" }
        let units = ["B/s", "K/s", "M/s", "G/s"]
        var scaled = max(0, value)
        var unitIndex = 0
        while scaled >= 1024, unitIndex < units.count - 1 {
            scaled /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(Int(scaled.rounded()))\(units[unitIndex])"
        }
        return String(format: "%.1f%@", scaled, units[unitIndex])
    }

    static func statusBarNetworkSpeed(_ value: Double?) -> String {
        // ↓/↑ prefix + 5-char value = fixed 6-char slot
        guard let value else { return "↓\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}" }
        let bps = max(0, value)
        let KB = bps / 1024

        let body: String
        if KB < 1 {
            body = pad("\(Int(bps.rounded()))B", to: 5)
        } else if KB < 10 {
            body = pad(String(format: "%.1fK", KB), to: 5)
        } else if KB < 100 {
            body = pad("\(Int(KB.rounded()))K", to: 5)
        } else if KB < 10_000 {
            body = pad(String(format: "%.0fK", KB), to: 5)
        } else {
            let MB = KB / 1024
            if MB < 10 {
                body = pad(String(format: "%.1fM", MB), to: 5)
            } else if MB < 100 {
                body = pad("\(Int(MB.rounded()))M", to: 5)
            } else {
                let GB = MB / 1024
                body = pad(String(format: "%.1fG", GB), to: 5)
            }
        }
        return "↓" + body
    }

    static func statusBarNetworkSpeedUp(_ value: Double?) -> String {
        // Same as statusBarNetworkSpeed but with ↑ prefix
        guard let value else { return "↑\u{2007}\u{2007}\u{2007}\u{2007}\u{2007}" }
        let bps = max(0, value)
        let KB = bps / 1024

        let body: String
        if KB < 1 {
            body = pad("\(Int(bps.rounded()))B", to: 5)
        } else if KB < 10 {
            body = pad(String(format: "%.1fK", KB), to: 5)
        } else if KB < 100 {
            body = pad("\(Int(KB.rounded()))K", to: 5)
        } else if KB < 10_000 {
            body = pad(String(format: "%.0fK", KB), to: 5)
        } else {
            let MB = KB / 1024
            if MB < 10 {
                body = pad(String(format: "%.1fM", MB), to: 5)
            } else if MB < 100 {
                body = pad("\(Int(MB.rounded()))M", to: 5)
            } else {
                let GB = MB / 1024
                body = pad(String(format: "%.1fG", GB), to: 5)
            }
        }
        return "↑" + body
    }

    private static func pad(_ s: String, to width: Int) -> String {
        let deficit = width - s.count
        guard deficit > 0 else { return s }
        return String(repeating: "\u{2007}", count: deficit) + s
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "从未" }
        return value.formatted(date: .omitted, time: .standard)
    }

    static func age(_ value: Date?) -> String {
        guard let value else { return "暂无数据" }
        let seconds = max(0, Int(Date().timeIntervalSince(value)))
        if seconds < 60 {
            return "\(seconds) 秒前"
        }
        return "\(seconds / 60) 分钟前"
    }
}
