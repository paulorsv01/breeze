import Foundation

public struct PresetConfiguration: Codable, Equatable, Sendable {
    public var minimumFraction: Double
    public var startTemperature: Double
    public var fullTemperature: Double

    public init(minimumFraction: Double, startTemperature: Double, fullTemperature: Double) {
        self.minimumFraction = minimumFraction
        self.startTemperature = startTemperature
        self.fullTemperature = fullTemperature
    }

    public static func defaults(for preset: FanPreset) -> Self {
        Self(minimumFraction: preset == .performancePlus ? 1 : 0.6, startTemperature: 40, fullTemperature: 75)
    }

    public func validate() throws {
        guard minimumFraction.isFinite, (0.3...1).contains(minimumFraction),
              startTemperature.isFinite, (30...65).contains(startTemperature),
              fullTemperature.isFinite, (50...85).contains(fullTemperature),
              fullTemperature >= startTemperature + 5 else {
            throw FanError.invalidReading("Invalid preset configuration.")
        }
    }
}
