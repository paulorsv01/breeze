import CSMC
import Foundation

public final class SMCConnection {
    private var connection: UInt32 = 0
    private var temperatureKeys: [String]?
    private lazy var manualControl = SMCManualControl(
        read: { [unowned self] in try number($0) },
        write: { [unowned self] in try write($0, number: $1) }
    )

    public init() throws {
        let status = breeze_smc_open(&connection)
        guard status == 0 else { throw FanError.smc(key: "AppleSMC", code: status, operation: .open) }
    }

    deinit { breeze_smc_close(connection) }

    private func code(_ key: String) -> UInt32 {
        key.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func read(_ key: String) throws -> BreezeSMCValue {
        guard key.utf8.count == 4 else { throw FanError.invalidReading("Invalid SMC key.") }
        var value = BreezeSMCValue()
        let status = breeze_smc_read(connection, code(key), &value)
        guard status == 0 else { throw FanError.smc(key: key, code: status, operation: .read) }
        return value
    }

    public func number(_ key: String) throws -> Double {
        var value = try read(key)
        let bytes = withUnsafeBytes(of: &value.bytes) { Array($0.prefix(Int(value.size))) }
        let result: Double
        switch (value.type, value.size) {
        case (code("flt "), 4):
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            result = Double(Float(bitPattern: bits))
        case (code("ui8 "), 1), (code("flag"), 1): result = Double(bytes[0])
        case (code("ui16"), 2): result = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case (code("ui32"), 4): result = Double(bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        case (code("sp78"), 2): result = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default: throw FanError.invalidReading("Unsupported SMC format at \(key).")
        }
        guard result.isFinite else { throw FanError.invalidReading("Invalid reading at \(key).") }
        return result
    }

    private func write(_ key: String, number: Double) throws {
        var value = try read(key)
        let bytes: [UInt8]
        switch (value.type, value.size) {
        case (code("flt "), 4):
            var bits = Float(number).bitPattern.littleEndian
            bytes = withUnsafeBytes(of: &bits, Array.init)
        case (code("ui8 "), 1), (code("flag"), 1):
            guard number == 0 || number == 1 else { throw FanError.invalidReading("Invalid mode.") }
            bytes = [UInt8(number)]
        default: throw FanError.invalidReading("Unsupported write at \(key).")
        }
        withUnsafeMutableBytes(of: &value.bytes) { $0.copyBytes(from: bytes) }
        let status = breeze_smc_write(connection, code(key), &value)
        guard status == 0 else { throw FanError.smc(key: key, code: status, operation: .write) }
    }

    private func modeKey(_ id: Int) throws -> String {
        for key in ["F\(id)Md", "F\(id)md"] {
            do { _ = try read(key); return key }
            catch FanError.smc(_, let code, .read) where code == 0x10084 { continue }
        }
        throw FanError.unavailable("This Mac does not expose compatible fan control.")
    }

    public func snapshot() throws -> FanSnapshot {
        let count = try number("FNum")
        guard count.rounded() == count, (1...10).contains(count) else {
            throw FanError.unavailable("No compatible fans found on this Mac.")
        }
        let fans = try (0..<Int(count)).map { id in
            let limits = try FanLimits(minimum: number("F\(id)Mn"), maximum: number("F\(id)Mx"))
            let rpm = try number("F\(id)Ac")
            let target = try number("F\(id)Tg")
            let mode = try number(modeKey(id))
            guard rpm >= 0, rpm <= 30_000, target >= 0, target <= 30_000,
                  [0.0, 1.0, 3.0].contains(mode) else {
                throw FanError.invalidReading("Invalid reading for fan \(id + 1).")
            }
            return FanReading(id: id, rpm: rpm, target: target, limits: limits, mode: Int(mode))
        }
        return FanSnapshot(fans: fans, temperature: try hottestTemperature())
    }

    private func hottestTemperature() throws -> Double? {
        if temperatureKeys == nil {
            let count = try number("#KEY")
            guard (1...20_000).contains(count) else { throw FanError.invalidReading("Invalid SMC catalog.") }
            var keys: [String] = []
            for index in 0..<UInt32(count) {
                var key: UInt32 = 0
                let status = breeze_smc_key_at(connection, index, &key)
                guard status == 0 else { throw FanError.smc(key: "#KEY[\(index)]", code: status, operation: .enumerate) }
                let bytes = [UInt8((key >> 24) & 255), UInt8((key >> 16) & 255), UInt8((key >> 8) & 255), UInt8(key & 255)]
                let name = String(decoding: bytes, as: UTF8.self)
                if name.hasPrefix("Tp") || name.hasPrefix("Tg") { keys.append(name) }
            }
            temperatureKeys = keys
        }
        return temperatureKeys?.compactMap { key -> Double? in
            guard let value = try? number(key), (1...120).contains(value) else { return nil }
            return value
        }.max()
    }

    public func releaseControl(recovering: Bool) throws { try manualControl.release(recovering: recovering) }

    public func setAutomatic(fan id: Int) throws {
        guard (0...9).contains(id) else { throw FanError.invalidReading("Invalid fan.") }
        let key = try modeKey(id)
        let mode = try number(key)
        if mode != 3 { try write(key, number: 0) }
        try confirmMode(key, automatic: true)
    }

    public func setTarget(fan: FanReading, rpm: Double) throws {
        guard rpm.isFinite, (fan.limits.minimum...fan.limits.maximum).contains(rpm) else {
            throw FanError.invalidReading("RPM outside fan limits.")
        }
        let key = try modeKey(fan.id)
        if try number(key) != 1 {
            try manualControl.enable(key: key)
            try confirmMode(key, automatic: false)
        }
        try write("F\(fan.id)Tg", number: rpm)
        try confirmMode(key, automatic: false)
    }

    private func confirmMode(_ key: String, automatic: Bool) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        var confirmations = 0
        repeat {
            let mode = try number(key)
            let matches = automatic ? (mode == 0 || mode == 3) : mode == 1
            confirmations = matches ? confirmations + 1 : 0
            if confirmations == 3 { return }
            Thread.sleep(forTimeInterval: 0.05)
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw FanError.unavailable(automatic
            ? "SMC did not confirm automatic mode. Restoration will be retried."
            : "SMC did not confirm manual mode. Restoring automatic mode.")
    }
}
