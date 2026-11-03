import Foundation
import Testing
@testable import BreezeCore

private final class TestHardware: FanHardware {
    var temperature: Double? = 50
    var failTarget: Int?
    var failAutomatic: Set<Int> = []
    var failReading = false
    var failRelease = false
    var controlReleased = false
    var onTarget: (() -> Void)?
    var manual: Set<Int> = []
    var targets: [Int: Double] = [:]
    var restored: [Int] = []
    let fanCount: Int
    let limits: FanLimits

    init(fanCount: Int = 1) throws {
        self.fanCount = fanCount
        limits = try FanLimits(minimum: 1700, maximum: 5000)
    }

    func snapshot() throws -> FanSnapshot {
        if failReading { throw FanError.unavailable("Leitura falhou.") }
        return FanSnapshot(fans: (0..<fanCount).map {
            FanReading(id: $0, rpm: 2000, target: targets[$0] ?? 2000, limits: limits, mode: manual.contains($0) ? 1 : 0)
        }, temperature: temperature)
    }

    func releaseControl(recovering: Bool) throws {
        #expect(manual.isEmpty)
        if failRelease { throw FanError.unavailable("Release failed") }
        controlReleased = true
    }

    func setAutomatic(fan id: Int) throws {
        if failAutomatic.contains(id) { throw FanError.unavailable("Restauração falhou.") }
        manual.remove(id)
        restored.append(id)
    }

    func setTarget(fan: FanReading, rpm: Double) throws {
        manual.insert(fan.id)
        if failTarget == fan.id { throw FanError.unavailable("Escrita falhou depois de ativar manual.") }
        targets[fan.id] = rpm
        onTarget?()
    }
}

@Test func curveRespectsHardwareLimitsAndOrder() throws {
    let limits = try FanLimits(minimum: 1700, maximum: 5000)
    var previous = 0.0
    for temperature in stride(from: -10.0, through: 120.0, by: 1) {
        let target = try #require(FanPreset.performance.target(in: limits, temperature: temperature))
        #expect(target >= limits.minimum && target <= limits.maximum)
        #expect(target >= previous)
        #expect(FanPreset.performancePlus.target(in: limits, temperature: temperature) == 5000)
        previous = target
    }
    #expect(FanPreset.standard.target(in: limits, temperature: 100) == nil)
    #expect(FanPreset.performance.target(in: limits, temperature: 40) == 3000)
    #expect(FanPreset.performance.target(in: limits, temperature: 75) == 5000)
}

@Test func missingOrInvalidTemperatureUsesMaximum() throws {
    let limits = try FanLimits(minimum: 1700, maximum: 5000)
    for temperature: Double? in [nil, .nan, .infinity] {
        #expect(FanPreset.performance.target(in: limits, temperature: temperature) == 5000)
    }
}

@Test func highHardwareMinimumIsRespected() throws {
    let limits = try FanLimits(minimum: 4500, maximum: 5000)
    #expect(FanPreset.performance.target(in: limits, temperature: 30) == 4500)
}

@Test func invalidLimitsAreRejected() {
    for (minimum, maximum) in [(-1.0, 5000.0), (5000, 5000), (6000, 5000), (0, 40_000), (.nan, 5000), (0, .infinity)] {
        #expect(throws: (any Error).self) { try FanLimits(minimum: minimum, maximum: maximum) }
    }
}

@Test func watchdogRestoresAfterLeaseExpires() throws {
    let hardware = try TestHardware(fanCount: 2)
    let controller = FanController(hardware: hardware)
    try controller.apply(.performance, owner: UUID(), now: 0)
    controller.tick(now: 7)
    #expect(hardware.manual == [0, 1])
    controller.tick(now: 8)
    #expect(hardware.manual.isEmpty)
    #expect(controller.preset == .standard)
}

@Test func heartbeatExtendsLeaseOnlyForOwner() throws {
    let hardware = try TestHardware()
    let controller = FanController(hardware: hardware)
    let session = UUID()
    try controller.apply(.performancePlus, owner: session, now: 0)
    controller.heartbeat(owner: session, now: 6)
    controller.tick(now: 8)
    #expect(controller.preset == .performancePlus)
    controller.heartbeat(owner: UUID(), now: 13)
    controller.tick(now: 14)
    #expect(controller.preset == .standard)
}

@Test func partialWriteRestoresEveryTouchedFan() throws {
    let hardware = try TestHardware(fanCount: 2)
    hardware.failTarget = 1
    let controller = FanController(hardware: hardware)
    #expect(throws: (any Error).self) { try controller.apply(.performance, owner: UUID(), now: 0) }
    #expect(hardware.manual.isEmpty)
    #expect(Set(hardware.restored) == [0, 1])
    #expect(controller.preset == .standard)
    #expect(controller.status.message != nil)
}

@Test func restoreFailuresAreRetriedWithoutClaimingAutomatic() throws {
    let hardware = try TestHardware(fanCount: 2)
    let controller = FanController(hardware: hardware)
    let owner = UUID()
    try controller.apply(.performancePlus, owner: owner, now: 0)
    hardware.failAutomatic = [0]
    #expect(throws: (any Error).self) { try controller.apply(.standard, owner: owner, now: 1) }
    #expect(controller.status.restoring)
    #expect(controller.preset == .performancePlus)
    #expect(hardware.manual == [0])
    hardware.failAutomatic = []
    controller.tick(now: 2)
    #expect(hardware.manual.isEmpty)
    #expect(controller.preset == .standard)
    #expect(!controller.status.restoring)
}

@Test func staleConnectionCannotResetNewOwner() throws {
    let hardware = try TestHardware()
    let controller = FanController(hardware: hardware)
    let old = UUID(), current = UUID()
    try controller.apply(.performance, owner: old, now: 0)
    controller.disconnect(owner: old)
    try controller.apply(.performancePlus, owner: current, now: 1)
    controller.disconnect(owner: old)
    #expect(controller.preset == .performancePlus)
    controller.disconnect(owner: current)
    #expect(controller.preset == .standard)
}

@Test func secondClientCannotTakeOver() throws {
    let hardware = try TestHardware()
    let controller = FanController(hardware: hardware)
    try controller.apply(.performancePlus, owner: UUID(), now: 0)
    #expect(throws: (any Error).self) { try controller.apply(.standard, owner: UUID(), now: 1) }
    #expect(controller.preset == .performancePlus)
}

@Test func readingFailureWhileActiveRestoresAutomatic() throws {
    let hardware = try TestHardware()
    let controller = FanController(hardware: hardware)
    try controller.apply(.performance, owner: UUID(), now: 0)
    hardware.failReading = true
    controller.tick(now: 1)
    #expect(hardware.manual.isEmpty)
    #expect(controller.preset == .standard)
}

@Test func restartRecoversManualFans() throws {
    let hardware = try TestHardware(fanCount: 2)
    hardware.manual = [0, 1]
    let controller = FanController(hardware: hardware)
    try controller.recoverAfterRestart()
    #expect(hardware.manual.isEmpty)
    #expect(controller.preset == .standard)
}

@Test func temperatureChangesUpdateActiveTarget() throws {
    let hardware = try TestHardware()
    let controller = FanController(hardware: hardware)
    hardware.temperature = 40
    try controller.apply(.performance, owner: UUID(), now: 0)
    #expect(hardware.targets[0] == 3000)
    hardware.temperature = 80
    controller.tick(now: 1)
    #expect(hardware.targets[0] == 5000)
}

@Test func customCurveIsAppliedAndRetainedAcrossTicks() throws {
    let hardware = try TestHardware()
    let controller = FanController(hardware: hardware)
    let curve = PresetConfiguration(minimumFraction: 0.4, startTemperature: 50, fullTemperature: 80)
    try controller.apply(.performancePlus, owner: UUID(), now: 0, configuration: curve)
    #expect(hardware.targets[0] == 2000)
    hardware.temperature = 65
    controller.tick(now: 1)
    #expect(hardware.targets[0] == 3500)
    hardware.temperature = 90
    controller.tick(now: 2)
    #expect(hardware.targets[0] == 5000)
    controller.tick(now: 8)
    #expect(hardware.manual.isEmpty)
}

@Test func invalidConfigurationCannotChangeActiveControl() throws {
    let hardware = try TestHardware()
    let controller = FanController(hardware: hardware)
    let owner = UUID()
    try controller.apply(.performancePlus, owner: owner, now: 0)
    for curve in [
        PresetConfiguration(minimumFraction: 0.1, startTemperature: 40, fullTemperature: 75),
        PresetConfiguration(minimumFraction: .nan, startTemperature: 40, fullTemperature: 75),
        PresetConfiguration(minimumFraction: 0.5, startTemperature: 60, fullTemperature: 60),
        PresetConfiguration(minimumFraction: 0.5, startTemperature: 40, fullTemperature: 100),
        PresetConfiguration(minimumFraction: 0.5, startTemperature: -.infinity, fullTemperature: 75)
    ] {
        #expect(throws: (any Error).self) {
            try controller.apply(.performance, owner: owner, now: 1, configuration: curve)
        }
        #expect(controller.preset == .performancePlus)
        #expect(hardware.targets[0] == 5000)
    }
    controller.tick(now: 8)
    #expect(hardware.manual.isEmpty)
}

@Test func decodedConfigurationIsValidatedBeforeHardwareAccess() throws {
    let hardware = try TestHardware()
    let controller = FanController(hardware: hardware)
    let payload = Data(#"{"minimumFraction":4,"startTemperature":40,"fullTemperature":75}"#.utf8)
    let curve = try JSONDecoder().decode(PresetConfiguration.self, from: payload)
    #expect(throws: (any Error).self) {
        try controller.apply(.performance, owner: UUID(), now: 0, configuration: curve)
    }
    #expect(hardware.manual.isEmpty)
    #expect(hardware.targets.isEmpty)
}

@Test func customCurveStillRespectsHardwareAndMissingSensors() throws {
    let limits = try FanLimits(minimum: 4500, maximum: 5000)
    let curve = PresetConfiguration(minimumFraction: 0.3, startTemperature: 30, fullTemperature: 50)
    #expect(FanPreset.performance.target(in: limits, temperature: 20, configuration: curve) == 4500)
    #expect(FanPreset.performance.target(in: limits, temperature: nil, configuration: curve) == 5000)
    #expect(FanPreset.performance.target(in: limits, temperature: .nan, configuration: curve) == 5000)
    #expect(FanPreset.standard.target(in: limits, temperature: 100, configuration: curve) == nil)
}

@Test func leaseStartsAfterSlowFirmwareHandshake() throws {
    let hardware = try TestHardware()
    let controller = FanController(hardware: hardware)
    var time = 0.0
    hardware.onTarget = { time = 10 }
    try controller.apply(.performance, owner: UUID(), now: time)
    #expect(controller.preset == .performance)
    controller.tick(now: 17)
    #expect(controller.preset == .performance)
    controller.tick(now: 18)
    #expect(controller.preset == .standard)
    #expect(hardware.controlReleased)
}

@Test func unlockReleaseWaitsForEveryFanAndRetriesFailures() throws {
    let hardware = try TestHardware(fanCount: 2)
    let controller = FanController(hardware: hardware)
    try controller.apply(.performance, owner: UUID(), now: 0)
    hardware.failAutomatic = [1]
    controller.tick(now: 8)
    #expect(controller.status.restoring)
    #expect(!hardware.controlReleased)
    hardware.failAutomatic = []
    hardware.failRelease = true
    controller.tick(now: 9)
    #expect(hardware.manual.isEmpty)
    #expect(controller.status.restoring)
    #expect(controller.preset == .performance)
    hardware.failRelease = false
    controller.tick(now: 10)
    #expect(hardware.controlReleased)
    #expect(!controller.status.restoring)
    #expect(controller.preset == .standard)
}
