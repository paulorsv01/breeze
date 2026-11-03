import Foundation
import Testing
@testable import BreezeCore

@MainActor
private final class UpdateFixture {
    let expected = HelperInstallation(bundlePath: "/Applications/Breeze.app", digest: "new")
    var events: [String] = []
    var approved = true
    var restoreFails = false
    var staleReply = false
    let updater = HelperUpdater()

    func status(_ installation: HelperInstallation? = nil, preset: FanPreset = .standard) -> ControlStatus {
        var status = ControlStatus(preset: preset, message: nil, restoring: false)
        status.installation = installation
        return status
    }

    func run(_ current: ControlStatus?) async throws -> ControlStatus? {
        try await updater.reconcile(expected: expected, current: current, restore: {
            self.events.append("restore")
            if self.restoreFails { throw FanError.unavailable("restore failed") }
            return self.status()
        }, register: {
            self.events.append("register")
            return self.approved
        }, probe: {
            self.events.append("probe")
            return self.status(self.staleReply ? nil : self.expected)
        }, wait: { seconds in self.events.append("wait:\(seconds)") })
    }
}

@Test @MainActor func matchingHelperNeedsNoUpdate() async throws {
    let fixture = UpdateFixture()
    let status = try await fixture.run(fixture.status(fixture.expected, preset: .performance))
    #expect(status?.preset == .performance)
    #expect(fixture.events.isEmpty)
}

@Test @MainActor func oldHelperRestoresBeforeRegisteringAndVerifiesReplacement() async throws {
    let fixture = UpdateFixture()
    let old = HelperInstallation(bundlePath: fixture.expected.bundlePath, digest: "old")
    let status = try await fixture.run(fixture.status(old, preset: .performance))
    #expect(status?.installation == fixture.expected)
    #expect(fixture.events == ["restore", "register", "probe"])
}

@Test @MainActor func sameBinaryAtOldPathIsUpdated() async throws {
    let fixture = UpdateFixture()
    let moved = HelperInstallation(bundlePath: "/old/Breeze.app", digest: "new")
    _ = try await fixture.run(fixture.status(moved))
    #expect(fixture.events == ["restore", "register", "probe"])
}

@Test @MainActor func releasedHelperWithoutIdentityIsUpdated() async throws {
    let fixture = UpdateFixture()
    _ = try await fixture.run(fixture.status())
    #expect(fixture.events == ["restore", "register", "probe"])
    let decoded = try JSONDecoder().decode(ControlStatus.self, from: Data(#"{"preset":"standard","restoring":false}"#.utf8))
    #expect(decoded.installation == nil)
}

@Test @MainActor func unreachableHelperWaitsForLeaseBeforeReplacing() async throws {
    let fixture = UpdateFixture()
    _ = try await fixture.run(nil)
    #expect(fixture.events == ["wait:9.0", "register", "probe"])
}

@Test @MainActor func failedRestorationDoesNotReplaceService() async {
    let fixture = UpdateFixture()
    fixture.restoreFails = true
    await #expect(throws: (any Error).self) { try await fixture.run(fixture.status()) }
    #expect(fixture.events == ["restore"])
}

@Test @MainActor func deniedApprovalDoesNotProbeOrRetryRegistration() async throws {
    let fixture = UpdateFixture()
    fixture.approved = false
    let result = try await fixture.run(fixture.status())
    #expect(result == nil)
    #expect(fixture.events == ["restore", "register"])
}

@Test @MainActor func wrongReplacementStopsAfterBoundedVerification() async {
    let fixture = UpdateFixture()
    fixture.staleReply = true
    await #expect(throws: (any Error).self) { try await fixture.run(fixture.status()) }
    await #expect(throws: (any Error).self) { try await fixture.run(fixture.status()) }
    #expect(fixture.events.filter { $0 == "register" }.count == 1)
    #expect(fixture.events.filter { $0 == "probe" }.count == 5)
}
