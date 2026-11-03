import Foundation

public struct PresetConfiguration: Codable, Equatable, Sendable {
    public var minimumFraction: Double
    public var startTemperature: Double
    public var fullTemperature: Double
    public var hysteresis: Double

    public init(minimumFraction: Double, startTemperature: Double, fullTemperature: Double, hysteresis: Double = 5) {
        self.minimumFraction = minimumFraction
        self.startTemperature = startTemperature
        self.fullTemperature = fullTemperature
        self.hysteresis = hysteresis
    }

    public static func defaults(for preset: FanPreset) -> Self {
        Self(minimumFraction: preset == .performancePlus ? 1 : 0.6, startTemperature: 40, fullTemperature: 75)
    }

    private enum CodingKeys: String, CodingKey {
        case minimumFraction, startTemperature, fullTemperature, hysteresis
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        minimumFraction = try values.decode(Double.self, forKey: .minimumFraction)
        startTemperature = try values.decode(Double.self, forKey: .startTemperature)
        fullTemperature = try values.decode(Double.self, forKey: .fullTemperature)
        hysteresis = try values.decodeIfPresent(Double.self, forKey: .hysteresis) ?? 5
    }

    public func fraction(at temperature: Double) -> Double {
        let progress = min(1, max(0, (temperature - startTemperature) / (fullTemperature - startTemperature)))
        return minimumFraction + (1 - minimumFraction) * progress
    }

    public func controlTemperature(measured: Double?, previous: Double?) -> Double {
        guard let measured, measured.isFinite else { return fullTemperature }
        let current = min(fullTemperature, measured)
        guard let previous else { return max(startTemperature, current) }
        return max(startTemperature, max(current, min(previous, current + hysteresis)))
    }

    public func validate() throws {
        guard minimumFraction.isFinite, (0.3...1).contains(minimumFraction),
              startTemperature.isFinite, (30...65).contains(startTemperature),
              fullTemperature.isFinite, (50...85).contains(fullTemperature),
              fullTemperature >= startTemperature + 5,
              hysteresis.isFinite, (0...10).contains(hysteresis) else {
            throw FanError.invalidReading("Invalid preset configuration.")
        }
    }
}
