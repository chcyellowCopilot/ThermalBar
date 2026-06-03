import Foundation
import IOKit

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

    func readKey(_ key: String) throws -> (bytes: [UInt8], size: UInt32) {
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
        return (bytes, infoOut.keyInfo.dataSize)
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

    print(try json(["fanCount": fanCount, "fans": fans]))
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    print(try json(["fanCount": 0, "fans": [], "error": message]))
    exit(1)
}
