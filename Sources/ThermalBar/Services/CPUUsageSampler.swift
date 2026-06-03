import Darwin
import Foundation

struct CPUUsageSample: Equatable {
    let usagePercent: Double?
}

final class CPUUsageSampler {
    private var previousTicks: [UInt32]?

    func reset() {
        previousTicks = nil
    }

    func sample() -> CPUUsageSample {
        guard let ticks = currentTicks() else {
            previousTicks = nil
            return CPUUsageSample(usagePercent: nil)
        }

        defer { previousTicks = ticks }

        guard let previousTicks, previousTicks.count == ticks.count else {
            return CPUUsageSample(usagePercent: nil)
        }

        let user = Double(ticks[Int(CPU_STATE_USER)] - previousTicks[Int(CPU_STATE_USER)])
        let system = Double(ticks[Int(CPU_STATE_SYSTEM)] - previousTicks[Int(CPU_STATE_SYSTEM)])
        let nice = Double(ticks[Int(CPU_STATE_NICE)] - previousTicks[Int(CPU_STATE_NICE)])
        let idle = Double(ticks[Int(CPU_STATE_IDLE)] - previousTicks[Int(CPU_STATE_IDLE)])
        let active = user + system + nice
        let total = active + idle

        guard total > 0 else {
            return CPUUsageSample(usagePercent: nil)
        }

        return CPUUsageSample(usagePercent: active / total * 100)
    }

    private func currentTicks() -> [UInt32]? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return [
            info.cpu_ticks.0,
            info.cpu_ticks.1,
            info.cpu_ticks.2,
            info.cpu_ticks.3,
        ]
    }
}
