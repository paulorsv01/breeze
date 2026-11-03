import Foundation
import Testing
@testable import BreezeCore

@Test func coolingMarginHoldsSmallDropsAndReleasesGradually() {
    let curve = PresetConfiguration.defaults(for: .performance)
    var previous: Double?
    for (measured, expected) in [(60.0, 60.0), (59, 60), (60, 60), (55, 60), (54, 59), (55, 59), (61, 61)] {
        previous = curve.controlTemperature(measured: measured, previous: previous)
        #expect(previous == expected)
    }
}

@Test func hysteresisDoesNotHoldAboveMinimumWhenMacIsCold() {
    let curve = PresetConfiguration.defaults(for: .performance)
    #expect(curve.controlTemperature(measured: 20, previous: 44) == 40)
    #expect(curve.controlTemperature(measured: 35, previous: 44) == 40)
}

@Test func fullSpeedIsImmediateAndOverheatDoesNotExtendCoolingMargin() {
    let curve = PresetConfiguration.defaults(for: .performance)
    let hot = curve.controlTemperature(measured: 120, previous: 40)
    #expect(hot == 75)
    #expect(curve.controlTemperature(measured: 69, previous: hot) == 74)
}

@Test func zeroCoolingMarginFollowsTemperatureDirectly() {
    var curve = PresetConfiguration.defaults(for: .performance)
    curve.hysteresis = 0
    #expect(curve.controlTemperature(measured: 50, previous: 70) == 50)
}

@Test func missingSensorsKeepFullSpeedUntilCoolingIsConfirmed() {
    let curve = PresetConfiguration.defaults(for: .performance)
    for temperature: Double? in [nil, .nan, .infinity] {
        let missing = curve.controlTemperature(measured: temperature, previous: 50)
        #expect(missing == 75)
        #expect(curve.controlTemperature(measured: 74, previous: missing) == 75)
    }
}

@Test func existingSavedCurvesKeepTheirLimitsWhenHysteresisIsAdded() throws {
    let saved = Data(#"{"minimumFraction":0.45,"startTemperature":45,"fullTemperature":70}"#.utf8)
    let curve = try JSONDecoder().decode(PresetConfiguration.self, from: saved)
    #expect(curve.minimumFraction == 0.45)
    #expect(curve.startTemperature == 45)
    #expect(curve.fullTemperature == 70)
    #expect(curve.hysteresis == 5)
    #expect(try JSONDecoder().decode(PresetConfiguration.self, from: JSONEncoder().encode(curve)) == curve)
}

@Test func coolingMarginIsValidatedAtTheControlBoundary() {
    for margin in [-1.0, 11, .nan, .infinity] {
        let curve = PresetConfiguration(minimumFraction: 0.6, startTemperature: 40, fullTemperature: 75, hysteresis: margin)
        #expect(throws: (any Error).self) { try curve.validate() }
    }
}
