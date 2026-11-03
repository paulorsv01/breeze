import Foundation

public protocol FanHardware: AnyObject {
    func snapshot() throws -> FanSnapshot
    func setAutomatic(fan id: Int) throws
    func setTarget(fan: FanReading, rpm: Double) throws
}

extension SMCConnection: FanHardware {}

public struct ControlStatus: Codable, Sendable {
    public let preset: FanPreset
    public let message: String?
    public let restoring: Bool
}

public final class FanController {
    public private(set) var preset: FanPreset = .standard
    public private(set) var message: String?
    private let hardware: any FanHardware
    private var configuration = PresetConfiguration.defaults(for: .performance)
    private var owner: UUID?
    private var deadline: TimeInterval = 0
    private var controlledFans: Set<Int> = []
    private var restoring = false
    public static let leaseDuration: TimeInterval = 8

    public init(hardware: any FanHardware) { self.hardware = hardware }

    public var status: ControlStatus {
        ControlStatus(preset: preset, message: message, restoring: restoring)
    }

    public func recoverAfterRestart() throws {
        let snapshot = try hardware.snapshot()
        controlledFans.formUnion(snapshot.fans.filter { $0.mode == 1 }.map(\.id))
        try restore()
    }

    public func apply(_ requested: FanPreset, owner session: UUID, now: TimeInterval, configuration: PresetConfiguration? = nil) throws {
        guard owner == nil || owner == session else {
            throw FanError.unavailable("Another instance is controlling the fans.")
        }
        if requested == .standard {
            try restore()
            message = nil
            return
        }
        guard !restoring else {
            throw FanError.unavailable("Waiting for automatic mode.")
        }
        let curve = configuration ?? .defaults(for: requested)
        try curve.validate()
        do {
            let snapshot = try hardware.snapshot()
            guard !snapshot.fans.isEmpty else { throw FanError.unavailable("No fan available.") }
            for fan in snapshot.fans {
                guard let target = requested.target(in: fan.limits, temperature: snapshot.temperature, configuration: curve) else { continue }
                controlledFans.insert(fan.id)
                try hardware.setTarget(fan: fan, rpm: target)
            }
            self.configuration = curve
            owner = session
            preset = requested
            deadline = now + Self.leaseDuration
            message = nil
        } catch {
            let failure = error.localizedDescription
            do { try restore() }
            catch { message = "\(failure) Automatic restoration pending: \(error.localizedDescription)"; throw error }
            message = failure
            throw error
        }
    }

    public func heartbeat(owner session: UUID, now: TimeInterval) {
        if owner == session, !restoring { deadline = now + Self.leaseDuration }
    }

    public func disconnect(owner session: UUID) {
        guard owner == session else { return }
        do { try restore() }
        catch { message = error.localizedDescription }
    }

    public func tick(now: TimeInterval) {
        if restoring || (owner != nil && now >= deadline) {
            do { try restore() }
            catch { message = error.localizedDescription }
            return
        }
        guard let owner, preset != .standard else { return }
        let remaining = deadline
        do {
            try apply(preset, owner: owner, now: now, configuration: configuration)
            deadline = remaining
        } catch { message = error.localizedDescription }
    }

    public func restore() throws {
        restoring = true
        var failures: [String] = []
        for id in controlledFans.sorted() {
            do { try hardware.setAutomatic(fan: id); controlledFans.remove(id) }
            catch { failures.append(error.localizedDescription) }
        }
        guard failures.isEmpty else {
            throw FanError.unavailable(failures.joined(separator: " "))
        }
        owner = nil
        preset = .standard
        restoring = false
    }
}
