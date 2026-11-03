import Foundation

public enum FanPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard, performance, performancePlus

    public var id: String { rawValue }
    public func target(in limits: FanLimits, temperature: Double?, configuration: PresetConfiguration? = nil) -> Double? {
        guard self != .standard else { return nil }
        let curve = configuration ?? .defaults(for: self)
        guard let temperature, temperature.isFinite else { return limits.maximum }
        let progress = min(1, max(0, (temperature - curve.startTemperature) / (curve.fullTemperature - curve.startTemperature)))
        let fraction = curve.minimumFraction + (1 - curve.minimumFraction) * progress
        return min(limits.maximum, max(limits.minimum, limits.maximum * fraction))
    }
}

public struct FanLimits: Codable, Equatable, Sendable {
    public let minimum: Double
    public let maximum: Double

    public init(minimum: Double, maximum: Double) throws {
        guard minimum.isFinite, maximum.isFinite, minimum >= 0,
              maximum > minimum, maximum <= 30_000 else {
            throw FanError.invalidReading("Invalid RPM limits.")
        }
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct FanReading: Codable, Identifiable, Sendable {
    public let id: Int
    public let rpm: Double
    public let target: Double
    public let limits: FanLimits
    public let mode: Int

    public init(id: Int, rpm: Double, target: Double, limits: FanLimits, mode: Int) {
        self.id = id
        self.rpm = rpm
        self.target = target
        self.limits = limits
        self.mode = mode
    }
}

public struct FanSnapshot: Codable, Sendable {
    public let fans: [FanReading]
    public let temperature: Double?

    public init(fans: [FanReading], temperature: Double?) {
        self.fans = fans
        self.temperature = temperature
    }
}

public enum FanError: LocalizedError {
    case smc(key: String, code: Int32)
    case invalidReading(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .smc(key, code): "SMC · \(key): error 0x\(String(UInt32(bitPattern: code), radix: 16))."
        case let .invalidReading(message), let .unavailable(message): message
        }
    }
}
