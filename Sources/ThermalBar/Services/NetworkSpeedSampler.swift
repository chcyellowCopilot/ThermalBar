import Darwin
import Foundation
import SystemConfiguration

struct NetworkSpeedSample: Equatable {
    let interface: String?
    let downloadBps: Double?
    let uploadBps: Double?
}

final class NetworkSpeedSampler {
    private struct Counters {
        let interface: String
        let rxBytes: UInt64
        let txBytes: UInt64
    }

    private var previous: (date: Date, counters: Counters)?

    func reset() {
        previous = nil
    }

    func sample() -> NetworkSpeedSample {
        guard let counters = currentCounters() else {
            previous = nil
            return NetworkSpeedSample(interface: nil, downloadBps: nil, uploadBps: nil)
        }

        let now = Date()
        defer { previous = (now, counters) }

        guard let previous,
              previous.counters.interface == counters.interface,
              counters.rxBytes >= previous.counters.rxBytes,
              counters.txBytes >= previous.counters.txBytes
        else {
            return NetworkSpeedSample(interface: counters.interface, downloadBps: nil, uploadBps: nil)
        }

        let elapsed = now.timeIntervalSince(previous.date)
        guard elapsed > 0 else {
            return NetworkSpeedSample(interface: counters.interface, downloadBps: nil, uploadBps: nil)
        }

        return NetworkSpeedSample(
            interface: counters.interface,
            downloadBps: Double(counters.rxBytes - previous.counters.rxBytes) / elapsed,
            uploadBps: Double(counters.txBytes - previous.counters.txBytes) / elapsed
        )
    }

    private func currentCounters() -> Counters? {
        let counters = interfaceCounters()
        if let primary = primaryInterface(),
           let primaryCounters = counters.first(where: { $0.interface == primary }) {
            return primaryCounters
        }

        return counters.max { left, right in
            left.rxBytes + left.txBytes < right.rxBytes + right.txBytes
        }
    }

    private func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "ThermalBar" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else {
            return nil
        }

        return value["PrimaryInterface"] as? String
    }

    private func interfaceCounters() -> [Counters] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else {
            return []
        }
        defer { freeifaddrs(addresses) }

        var result: [Counters] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let address = cursor {
            defer { cursor = address.pointee.ifa_next }

            guard let namePointer = address.pointee.ifa_name,
                  let socketAddress = address.pointee.ifa_addr,
                  Int32(socketAddress.pointee.sa_family) == AF_LINK,
                  let data = address.pointee.ifa_data else {
                continue
            }

            let name = String(cString: namePointer)
            guard !isExcludedInterface(name) else {
                continue
            }

            let interfaceData = data.assumingMemoryBound(to: if_data.self).pointee
            result.append(
                Counters(
                    interface: name,
                    rxBytes: UInt64(interfaceData.ifi_ibytes),
                    txBytes: UInt64(interfaceData.ifi_obytes)
                )
            )
        }

        return result.filter { $0.rxBytes > 0 || $0.txBytes > 0 }
    }

    private func isExcludedInterface(_ name: String) -> Bool {
        name == "lo0"
            || name.hasPrefix("awdl")
            || name.hasPrefix("llw")
            || name.hasPrefix("bridge")
    }
}
