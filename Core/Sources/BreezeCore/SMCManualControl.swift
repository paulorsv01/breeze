import Foundation

final class SMCManualControl {
    let read: (String) throws -> Double
    let write: (String, Double) throws -> Void
    private let uptime: () -> TimeInterval
    private let wait: (TimeInterval) -> Void
    private var releasePending = false

    init(
        read: @escaping (String) throws -> Double,
        write: @escaping (String, Double) throws -> Void,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        wait: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.read = read
        self.write = write
        self.uptime = uptime
        self.wait = wait
    }

    func enable(key: String) throws {
        do {
            try write(key, 1)
            return
        } catch let refusal as FanError {
            guard case .smc(_, 0x10082, .write) = refusal, try read(key) == 3 else { throw refusal }
            let forceTest: Double
            do { forceTest = try read("Ftst") }
            catch FanError.smc(_, 0x10084, .read) { throw refusal }
            guard forceTest == 0 || forceTest == 1 else { throw refusal }
            releasePending = true
            if forceTest == 0 { try write("Ftst", 1) }
        }

        let deadline = uptime() + 10
        while uptime() < deadline {
            switch try read(key) {
            case 1: return
            case 0:
                do { try write(key, 1); return }
                catch FanError.smc(_, 0x10082, .write) { break }
            case 3: break
            default: throw FanError.invalidReading("Invalid mode.")
            }
            wait(0.1)
        }
        throw FanError.unavailable("SMC did not release system mode. Restoring automatic mode.")
    }

    func release(recovering: Bool) throws {
        guard releasePending || recovering else { return }
        let forceTest: Double
        do { forceTest = try read("Ftst") }
        catch FanError.smc(_, 0x10084, .read) { releasePending = false; return }
        guard forceTest != 0 else { releasePending = false; return }
        guard forceTest == 1 else { throw FanError.invalidReading("Invalid mode.") }
        try write("Ftst", 0)
        guard try read("Ftst") == 0 else {
            throw FanError.unavailable("SMC did not release fan control. Restoration will be retried.")
        }
        releasePending = false
    }
}
