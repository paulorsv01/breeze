import CryptoKit
import Foundation

public struct HelperInstallation: Codable, Equatable, Sendable {
    public let bundlePath: String
    public let digest: String

    public init(bundlePath: String, digest: String) {
        self.bundlePath = bundlePath
        self.digest = digest
    }

    public init(bundleURL: URL) throws {
        let bundle = bundleURL.resolvingSymlinksInPath().standardizedFileURL
        var hash = SHA256()
        for path in ["Contents/Library/HelperTools/BreezeHelper", "Contents/Library/LaunchDaemons/com.breeze.fancontrol.Helper.plist"] {
            hash.update(data: try Data(contentsOf: bundle.appendingPathComponent(path)))
        }
        self.init(bundlePath: bundle.path, digest: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

@MainActor
public final class HelperUpdater {
    private var attempted = false

    public init() {}

    public func reconcile(
        expected: HelperInstallation,
        current: ControlStatus?,
        restore: () async throws -> ControlStatus,
        register: () async throws -> Bool,
        probe: () async throws -> ControlStatus,
        wait: (Double) async throws -> Void
    ) async throws -> ControlStatus? {
        if current?.installation == expected { return current }
        guard !attempted else {
            throw FanError.unavailable("The service update could not be confirmed. Reopen Breeze to retry.")
        }
        attempted = true
        if current != nil {
            let restored = try await restore()
            guard restored.preset == .standard, !restored.restoring, restored.message == nil else {
                throw FanError.unavailable("Could not restore automatic mode before updating the service.")
            }
        } else {
            // An unreachable older helper still owns an eight-second control lease.
            try await wait(FanController.leaseDuration + 1)
        }
        guard try await register() else { return nil }
        for attempt in 0..<5 {
            if attempt > 0 { try await wait(0.5) }
            if let status = try? await probe(), status.installation == expected { return status }
        }
        throw FanError.unavailable("The service update could not be confirmed. Reopen Breeze to retry.")
    }
}
