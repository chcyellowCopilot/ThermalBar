import Foundation
import IOKit
import IOKit.hidsystem

typealias IOHIDEventRef = CFTypeRef

@_silgen_name("IOHIDEventSystemClientCreateWithType")
private func IOHIDEventSystemClientCreateWithType(
    _ allocator: CFAllocator?,
    _ type: Int32,
    _ options: CFDictionary?
) -> IOHIDEventSystemClient

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(
    _ service: IOHIDServiceClient,
    _ type: Int64,
    _ matching: CFDictionary?,
    _ options: UInt32
) -> IOHIDEventRef?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: IOHIDEventRef, _ field: Int32) -> Double

private enum SMCCommand: UInt8 {
    case kernelIndex = 2
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCParamStruct {
    typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes32 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

private enum SMCReadError: LocalizedError {
    case serviceNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case firmware(UInt8)
    case malformedKey(String)

    var errorDescription: String? {
        switch self {
        case .serviceNotFound:
            "AppleSMC service not found"
        case .openFailed(let code):
            "IOServiceOpen failed: 0x\(String(code, radix: 16))"
        case .callFailed(let code):
            "IOConnectCallStructMethod failed: 0x\(String(code, radix: 16))"
        case .firmware(let code):
            "SMC firmware error: 0x\(String(code, radix: 16))"
        case .malformedKey(let key):
            "SMC key must be 4 ASCII bytes: \(key)"
        }
    }
}

private final class ReadOnlySMC {
    private let connection: io_connect_t

    init() throws {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC"),
            &iterator
        )
        guard result == kIOReturnSuccess else {
            throw SMCReadError.callFailed(result)
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            throw SMCReadError.serviceNotFound
        }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == kIOReturnSuccess else {
            throw SMCReadError.openFailed(openResult)
        }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    func readKey(_ key: String) throws -> (bytes: [UInt8], size: UInt32, type: String) {
        var info = SMCParamStruct()
        info.key = try fourCharCode(key)
        info.data8 = SMCCommand.readKeyInfo.rawValue
        let infoOut = try call(info)
        try checkFirmware(infoOut)

        var read = SMCParamStruct()
        read.key = info.key
        read.keyInfo.dataSize = infoOut.keyInfo.dataSize
        read.data8 = SMCCommand.readBytes.rawValue
        let readOut = try call(read)
        try checkFirmware(readOut)

        let bytes = withUnsafeBytes(of: readOut.bytes) {
            Array($0.prefix(Int(infoOut.keyInfo.dataSize)))
        }
        return (bytes, infoOut.keyInfo.dataSize, fourCharString(infoOut.keyInfo.dataType))
    }

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCCommand.kernelIndex.rawValue),
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else {
            throw SMCReadError.callFailed(result)
        }
        return output
    }

    private func checkFirmware(_ output: SMCParamStruct) throws {
        guard output.result == 0 else {
            throw SMCReadError.firmware(output.result)
        }
    }

    private func fourCharCode(_ key: String) throws -> UInt32 {
        let bytes = Array(key.utf8)
        guard bytes.count == 4 else {
            throw SMCReadError.malformedKey(key)
        }
        return bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func fourCharString(_ code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}

private func uint8(_ bytes: [UInt8]) -> UInt8? {
    bytes.first
}

private func rpmValue(bytes: [UInt8], size: UInt32) -> Double? {
    if size == 4, bytes.count >= 4 {
        return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
    }
    if bytes.count >= 2 {
        let raw = UInt16(bigEndian: bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) })
        return Double(raw) / 4.0
    }
    return nil
}

private func temperatureValue(bytes: [UInt8], size: UInt32, type: String) -> Double? {
    let value: Double?
    if type == "sp78", bytes.count >= 2 {
        value = Double(Int8(bitPattern: bytes[0])) + Double(bytes[1]) / 256.0
    } else if type == "flt ", size == 4, bytes.count >= 4 {
        value = Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
    } else if bytes.count >= 2 {
        let raw = UInt16(bigEndian: bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) })
        value = Double(raw) / 256.0
    } else {
        value = nil
    }

    guard let value, value >= 0, value <= 130 else {
        return nil
    }
    return value
}

private func hidDieTemperatures() -> [[String: Any]] {
    let temperatureEventType = 15
    let temperatureField = Int32(temperatureEventType << 16)
    let clientTypes: [Int32] = [1, 3]
    var readings: [[String: Any]] = []
    var seenProducts = Set<String>()

    for clientType in clientTypes {
        let client = IOHIDEventSystemClientCreateWithType(kCFAllocatorDefault, clientType, nil)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            continue
        }

        for service in services where IOHIDServiceClientConformsTo(service, 65280, 5) != 0 {
            guard let product = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  product.range(of: #"^PMU2? tdie\d+$"#, options: .regularExpression) != nil,
                  !seenProducts.contains(product),
                  let event = IOHIDServiceClientCopyEvent(service, Int64(temperatureEventType), nil, 0)
            else {
                continue
            }

            let temperature = IOHIDEventGetFloatValue(event, temperatureField)
            guard temperature >= 0, temperature <= 130 else {
                continue
            }

            seenProducts.insert(product)
            readings.append(["key": product, "temperatureC": temperature])
        }
    }

    return readings
}

private func json(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

do {
    let smc = try ReadOnlySMC()
    let countBytes = try smc.readKey("FNum").bytes
    let fanCount = Int(uint8(countBytes) ?? 0)
    var fans: [[String: Any]] = []

    for index in 0..<fanCount {
        let key = "F\(index)Ac"
        if let reading = try? smc.readKey(key),
           let rpm = rpmValue(bytes: reading.bytes, size: reading.size) {
            fans.append(["index": index, "rpm": rpm])
        } else {
            fans.append(["index": index, "rpm": NSNull()])
        }
    }

    let cpuTemperatureKeys = [
        "TC0P", "TC0E", "TC0F", "TC0H", "TC0D",
        "TC1P", "TC1E", "TC1F", "TC1H", "TC1D",
        "TC2P", "TC2E", "TC2F", "TC2H", "TC2D",
    ]
    var cpuTemperatures: [[String: Any]] = []
    for key in cpuTemperatureKeys {
        if let reading = try? smc.readKey(key),
           let temperature = temperatureValue(bytes: reading.bytes, size: reading.size, type: reading.type) {
            cpuTemperatures.append(["key": key, "temperatureC": temperature])
        }
    }
    cpuTemperatures.append(contentsOf: hidDieTemperatures())

    let cpuTemperature = cpuTemperatures
        .compactMap { $0["temperatureC"] as? Double }
        .max()

    print(try json([
        "fanCount": fanCount,
        "fans": fans,
        "cpuTemperatureC": cpuTemperature.map { $0 as Any } ?? NSNull(),
        "cpuTemperatureReadout": cpuTemperatures,
    ]))
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    print(try json(["fanCount": 0, "fans": [], "cpuTemperatureC": NSNull(), "cpuTemperatureReadout": [], "error": message]))
    exit(1)
}
