import Foundation
import Testing
@testable import BreezeCore

private final class SystemManagedSMC: FanHardware {
    var modes: [String: Double] = ["F0Md": 3, "F1Md": 3]
    var forceTest = 0.0
    var hasForceTest = true
    var unlockDelay = 3.5
    var now = 0.0
    var unlockedAt: Double?
    var refusal: Int32 = 0x10082
    var temperature = 40.0
    var targets: [Int: Double] = [:]
    lazy var control = makeControl()

    func read(_ key: String) throws -> Double {
        if key == "Ftst" {
            guard hasForceTest else { throw FanError.smc(key: key, code: 0x10084, operation: .read) }
            return forceTest
        }
        if let unlockedAt, now - unlockedAt >= unlockDelay, modes[key] == 3 { modes[key] = 0 }
        return try #require(modes[key])
    }

    func write(_ key: String, _ value: Double) throws {
        if key == "Ftst" {
            guard hasForceTest else { throw FanError.smc(key: key, code: 0x10084, operation: .read) }
            forceTest = value
            unlockedAt = value == 1 ? now : nil
            return
        }
        if value == 1, try read(key) == 3 { throw FanError.smc(key: key, code: refusal, operation: .write) }
        modes[key] = value
    }

    func makeControl() -> SMCManualControl {
        SMCManualControl(
            read: { [unowned self] in try read($0) },
            write: { [unowned self] in try write($0, $1) },
            uptime: { [unowned self] in now },
            wait: { [unowned self] in now += $0 }
        )
    }

    func snapshot() throws -> FanSnapshot {
        let limits = try FanLimits(minimum: 1000, maximum: 5000)
        return try FanSnapshot(fans: (0..<2).map { id in
            FanReading(id: id, rpm: 3000, target: targets[id] ?? 3000,
                       limits: limits, mode: Int(try read("F\(id)Md")))
        }, temperature: temperature)
    }

    func setTarget(fan: FanReading, rpm: Double) throws {
        let key = "F\(fan.id)Md"
        if try read(key) != 1 { try control.enable(key: key) }
        targets[fan.id] = rpm
    }

    func setAutomatic(fan id: Int) throws { try write("F\(id)Md", 0) }

    func releaseControl(recovering: Bool) throws { try control.release(recovering: recovering) }
}

@Test func manualControlRecoversAfterSystemReclaimsFan() throws {
    let smc = SystemManagedSMC()
    smc.modes["F0Md"] = 1
    // The firmware reclaims the mode between two curve updates.
    smc.modes["F0Md"] = 3
    try smc.control.enable(key: "F0Md")
    #expect(smc.modes["F0Md"] == 1)
    #expect(smc.forceTest == 1)
}

@Test func directManualControlDoesNotNeedForceTest() throws {
    let smc = SystemManagedSMC()
    smc.modes["F0Md"] = 0
    smc.hasForceTest = false
    try smc.control.enable(key: "F0Md")
    #expect(smc.modes["F0Md"] == 1)
    #expect(smc.forceTest == 0)
}

@Test func firmwareWithoutUnlockKeepsOriginalRefusal() {
    let smc = SystemManagedSMC()
    smc.hasForceTest = false
    do {
        try smc.control.enable(key: "F1Md")
        Issue.record("Manual mode incorrectly succeeded")
    } catch FanError.smc(let key, let code, let operation) {
        #expect(key == "F1Md")
        #expect(code == 0x10082)
        #expect(operation == .write)
    } catch { Issue.record("Original refusal was lost: \(error)") }
    #expect(smc.forceTest == 0)
}

@Test func unrelatedFirmwareErrorsDoNotTriggerUnlock() {
    let smc = SystemManagedSMC()
    smc.refusal = 0x10086
    #expect(throws: (any Error).self) { try smc.control.enable(key: "F0Md") }
    #expect(smc.forceTest == 0)
    #expect(smc.now == 0)
}

@Test func timedOutUnlockCanBeReleased() throws {
    let smc = SystemManagedSMC()
    smc.unlockDelay = 100
    let control = smc.control
    #expect(throws: (any Error).self) { try control.enable(key: "F0Md") }
    #expect(smc.now >= 10 && smc.now < 10.2)
    try control.release(recovering: false)
    #expect(smc.forceTest == 0)
}

@Test func releaseIsSharedAcrossFansAndRecoversAfterRestart() throws {
    let smc = SystemManagedSMC()
    let control = smc.control
    try control.enable(key: "F0Md")
    try control.enable(key: "F1Md")
    #expect(smc.modes.values.allSatisfy { $0 == 1 })
    smc.modes = ["F0Md": 0, "F1Md": 0]
    let restartedControl = smc.makeControl()
    try restartedControl.release(recovering: true)
    #expect(smc.forceTest == 0)
}

@Test func releaseDoesNotClearAnUnclaimedUnlock() throws {
    let smc = SystemManagedSMC()
    smc.forceTest = 1
    try smc.control.release(recovering: false)
    #expect(smc.forceTest == 1)
}

@Test func restartWithoutForceTestIsSupported() throws {
    let smc = SystemManagedSMC()
    smc.hasForceTest = false
    try smc.control.release(recovering: true)
}

@Test func failedUnlockWriteStillRequiresCleanup() throws {
    let smc = SystemManagedSMC()
    let control = SMCManualControl(read: smc.read, write: { key, value in
        try smc.write(key, value)
        if key == "Ftst" && value == 1 {
            throw FanError.smc(key: key, code: 0x10087, operation: .write)
        }
    })
    #expect(throws: (any Error).self) { try control.enable(key: "F0Md") }
    #expect(smc.forceTest == 1)
    try control.release(recovering: false)
    #expect(smc.forceTest == 0)
}

@Test func failedReleaseRemainsPendingUntilConfirmed() throws {
    let smc = SystemManagedSMC()
    var failRelease = true
    let control = SMCManualControl(read: smc.read, write: { key, value in
        if key == "Ftst" && value == 0 && failRelease { return }
        try smc.write(key, value)
    }, uptime: { smc.now }, wait: { smc.now += $0 })
    try control.enable(key: "F0Md")
    smc.modes["F0Md"] = 0
    #expect(throws: (any Error).self) { try control.release(recovering: false) }
    #expect(smc.forceTest == 1)
    failRelease = false
    try control.release(recovering: false)
    #expect(smc.forceTest == 0)
}

@Test func diagnosticIdentifiesTheFailedSMCOperation() {
    let reading = FanError.smc(key: "F0Md", code: 0x10082, operation: .read)
    let writing = FanError.smc(key: "F0Md", code: 0x10082, operation: .write)
    #expect(reading.localizedDescription.contains("read"))
    #expect(writing.localizedDescription.contains("write"))
}

@Test func temperatureUpdateRecoversManualModeWithoutDroppingPerformance() throws {
    let smc = SystemManagedSMC()
    smc.modes = ["F0Md": 0, "F1Md": 0]
    let controller = FanController(hardware: smc)
    try controller.apply(.performance, owner: UUID(), now: smc.now)
    #expect(controller.preset == .performance)
    #expect(smc.targets[0] == 3000)
    smc.temperature = 75
    smc.modes = ["F0Md": 3, "F1Md": 3]
    smc.now = 1
    controller.tick(now: smc.now)
    #expect(controller.preset == .performance)
    #expect(controller.status.message == nil)
    #expect(smc.targets[0] == 5000)
    #expect(smc.targets[1] == 5000)
    #expect(smc.forceTest == 1)
    smc.now = 8
    controller.tick(now: smc.now)
    #expect(controller.preset == .standard)
    #expect(smc.modes.values.allSatisfy { $0 == 0 })
    #expect(smc.forceTest == 0)
}

@Test func failedPeriodicRecoveryStillRestoresAutomaticAndReleasesUnlock() throws {
    let smc = SystemManagedSMC()
    smc.modes = ["F0Md": 0, "F1Md": 0]
    let controller = FanController(hardware: smc)
    try controller.apply(.performance, owner: UUID(), now: smc.now)
    smc.temperature = 75
    smc.modes = ["F0Md": 3, "F1Md": 3]
    smc.unlockDelay = 100
    smc.now = 1
    controller.tick(now: smc.now)
    #expect(controller.preset == .standard)
    #expect(controller.status.message != nil)
    #expect(smc.forceTest == 0)
    #expect(smc.modes.values.allSatisfy { $0 == 0 })
}

@Test func periodicUnlockCannotExtendAnExpiredClientLease() throws {
    let smc = SystemManagedSMC()
    smc.modes = ["F0Md": 0, "F1Md": 0]
    let controller = FanController(hardware: smc)
    try controller.apply(.performance, owner: UUID(), now: smc.now)
    smc.modes = ["F0Md": 3, "F1Md": 3]
    smc.now = 7
    controller.tick(now: smc.now)
    #expect(smc.now > 8)
    #expect(controller.preset == .standard)
    #expect(smc.forceTest == 0)
}
