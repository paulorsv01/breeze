import BreezeCore
import Foundation
import os

private struct ReplyGate: Sendable {
    private let state: OSAllocatedUnfairLock<CheckedContinuation<ControlStatus, Error>?>

    init(_ continuation: CheckedContinuation<ControlStatus, Error>) {
        state = OSAllocatedUnfairLock(initialState: continuation)
    }

    func finish(_ result: Result<ControlStatus, Error>) {
        let pending = state.withLock { continuation in
            let pending = continuation
            continuation = nil
            return pending
        }
        pending?.resume(with: result)
    }
}

@MainActor
final class HelperClient {
    private var connection: NSXPCConnection?

    func apply(_ preset: FanPreset, configuration: PresetConfiguration) async throws -> ControlStatus {
        let data = try JSONEncoder().encode(configuration)
        return try await request { proxy, reply in proxy.applyPreset(preset.rawValue, configuration: data, reply: reply) }
    }

    func heartbeat(timeout: TimeInterval = 15) async throws -> ControlStatus {
        try await request(timeout: timeout) { proxy, reply in proxy.heartbeat(reply: reply) }
    }

    func restore() async throws -> ControlStatus {
        try await request { proxy, reply in proxy.restore(reply: reply) }
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    private func connect() throws -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: HelperIdentity.helperID, options: .privileged)
        connection.setCodeSigningRequirement(try CodeIdentity.peerRequirement(identifier: HelperIdentity.helperID))
        connection.remoteObjectInterface = NSXPCInterface(with: BreezeHelperProtocol.self)
        connection.activate()
        self.connection = connection
        return connection
    }

    private func request(
        timeout: TimeInterval = 15,
        _ send: (any BreezeHelperProtocol, @escaping (Data?, String?) -> Void) -> Void
    ) async throws -> ControlStatus {
        let connection = try connect()
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let gate = ReplyGate(continuation)
                // Firmware may take up to ten seconds to release system mode.
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    gate.finish(.failure(FanError.unavailable("The service did not respond. Try again.")))
                }
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    gate.finish(.failure(error))
                }) as? BreezeHelperProtocol else {
                    gate.finish(.failure(FanError.unavailable("Could not connect to the service.")))
                    return
                }
                send(proxy) { data, message in
                    if let message { gate.finish(.failure(FanError.unavailable(message))); return }
                    guard let data else {
                        gate.finish(.failure(FanError.invalidReading("Empty service response.")))
                        return
                    }
                    do { gate.finish(.success(try JSONDecoder().decode(ControlStatus.self, from: data))) }
                    catch { gate.finish(.failure(error)) }
                }
            }
        } catch {
            invalidate()
            throw error
        }
    }
}
