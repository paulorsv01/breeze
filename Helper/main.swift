import BreezeCore
import Foundation
import OSLog
import MachO

private let runningInstallation: HelperInstallation? = {
    guard let path = _dyld_get_image_name(0) else { return nil }
    let executable = URL(fileURLWithPath: String(cString: path))
    let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try? HelperInstallation(bundleURL: bundle)
}()

private let logger = Logger(subsystem: HelperIdentity.helperID, category: "control")

final class HelperSession: NSObject, BreezeHelperProtocol {
    let id = UUID()
    private let controller: FanController

    init(controller: FanController) { self.controller = controller }

    func applyPreset(_ rawValue: String, configuration: Data, reply: @escaping (Data?, String?) -> Void) {
        DispatchQueue.main.async { [self] in
            guard let preset = FanPreset(rawValue: rawValue) else {
                reply(nil, "Invalid preset.")
                return
            }
            do {
                let curve = try JSONDecoder().decode(PresetConfiguration.self, from: configuration)
                try controller.apply(preset, owner: id, now: ProcessInfo.processInfo.systemUptime, configuration: curve)
                logger.info("Applied preset: \(rawValue, privacy: .public)")
                respond(reply)
            } catch { reply(nil, error.localizedDescription) }
        }
    }

    func heartbeat(reply: @escaping (Data?, String?) -> Void) {
        DispatchQueue.main.async { [self] in
            controller.heartbeat(owner: id, now: ProcessInfo.processInfo.systemUptime)
            respond(reply)
        }
    }

    func restore(reply: @escaping (Data?, String?) -> Void) {
        DispatchQueue.main.async { [self] in
            do {
                try controller.apply(.standard, owner: id, now: ProcessInfo.processInfo.systemUptime)
                respond(reply)
            } catch { reply(nil, error.localizedDescription) }
        }
    }

    func disconnected() {
        DispatchQueue.main.async { [self] in controller.disconnect(owner: id) }
    }

    private func respond(_ reply: (Data?, String?) -> Void) {
        var status = controller.status
        status.installation = runningInstallation
        do { reply(try JSONEncoder().encode(status), nil) }
        catch { reply(nil, error.localizedDescription) }
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    let controller: FanController
    init(controller: FanController) { self.controller = controller }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        let session = HelperSession(controller: controller)
        connection.exportedInterface = NSXPCInterface(with: BreezeHelperProtocol.self)
        connection.exportedObject = session
        connection.interruptionHandler = { session.disconnected() }
        connection.invalidationHandler = { session.disconnected() }
        connection.activate()
        return true
    }
}

do {
    _ = runningInstallation
    guard geteuid() == 0 else {
        throw FanError.unavailable("This service must be started by macOS as a LaunchDaemon.")
    }
    let hardware = try SMCConnection()
    let controller = FanController(hardware: hardware)
    try controller.recoverAfterRestart()
    let delegate = HelperDelegate(controller: controller)
    let listener = NSXPCListener(machServiceName: HelperIdentity.helperID)
    listener.setConnectionCodeSigningRequirement(try CodeIdentity.peerRequirement(identifier: HelperIdentity.appID))
    listener.delegate = delegate
    listener.activate()

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler { controller.tick(now: ProcessInfo.processInfo.systemUptime) }
    timer.resume()

    signal(SIGTERM, SIG_IGN)
    let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termination.setEventHandler {
        do { try controller.restore() }
        catch { logger.fault("Restoration failed: \(error.localizedDescription, privacy: .public)") }
        exit(0)
    }
    termination.resume()
    withExtendedLifetime((delegate, listener, timer, termination)) { dispatchMain() }
} catch {
    logger.fault("Service unavailable: \(error.localizedDescription, privacy: .public)")
    exit(1)
}
