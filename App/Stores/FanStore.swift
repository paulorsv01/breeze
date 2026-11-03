import AppKit
import BreezeCore
import Observation
import ServiceManagement

@MainActor @Observable
final class FanStore {
    enum ServiceState { case notRegistered, needsApproval, enabled, unavailable }

    private(set) var snapshot: FanSnapshot?
    private(set) var preset: FanPreset = .standard
    private(set) var serviceState: ServiceState = .notRegistered
    private(set) var busy = false
    private(set) var connectionReady = false
    private(set) var restoring = false
    private(set) var sensorError: String?
    private(set) var controlError: String?
    private(set) var loginEnabled = false
    private let reader = SensorReader()
    private let helper = HelperClient()
    private let service = SMAppService.daemon(plistName: HelperIdentity.plistName)
    private let defaults: UserDefaults
    private(set) var configurations: [String: PresetConfiguration] = [:]
    private var startupPreset: FanPreset?
    private var monitor: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "presetConfigurations"),
           let saved = try? JSONDecoder().decode([String: PresetConfiguration].self, from: data) {
            configurations = saved.filter { (try? $0.value.validate()) != nil }
        }
        startupPreset = defaults.string(forKey: "lastSelectedPreset").flatMap(FanPreset.init(rawValue:))
    }

    var canControl: Bool { connectionReady && !busy && !restoring }
    var error: String? { controlError ?? sensorError }
    var rpmLabel: String {
        guard let fan = snapshot?.fans.first else { return "—" }
        return Int(fan.rpm.rounded()).formatted(.number.grouping(.never))
    }

    func start() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refresh() async {
        loginEnabled = SMAppService.mainApp.status == .enabled
        refreshServiceState()
        do { snapshot = try await reader.snapshot(); sensorError = nil }
        catch { snapshot = nil; sensorError = error.localizedDescription }
        guard serviceState == .enabled else {
            connectionReady = false
            helper.invalidate()
            return
        }
        guard !busy else { return }
        do {
            let status = try await helper.heartbeat()
            guard !busy, !Task.isCancelled else { return }
            preset = status.preset
            restoring = status.restoring
            connectionReady = true
            controlError = status.message
            if let selected = startupPreset, !restoring {
                startupPreset = nil
                busy = true
                defer { busy = false }
                await apply(selected)
            }
        } catch {
            connectionReady = false
            controlError = error.localizedDescription
        }
    }

    private func refreshServiceState() {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents/Library")
        let plist = contents.appendingPathComponent("LaunchDaemons/\(HelperIdentity.plistName)")
        let executable = contents.appendingPathComponent("HelperTools/BreezeHelper")
        guard FileManager.default.fileExists(atPath: plist.path),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            serviceState = .unavailable
            return
        }
        switch service.status {
        case .enabled: serviceState = .enabled
        case .requiresApproval: serviceState = .needsApproval
        case .notRegistered, .notFound: serviceState = .notRegistered
        @unknown default: serviceState = .unavailable
        }
    }

    func activateService() {
        busy = true
        controlError = nil
        Task {
            defer {
                refreshServiceState()
                busy = false
            }
            do {
                try service.register()
            } catch {
                if service.status != .requiresApproval {
                    controlError = error.localizedDescription
                }
            }
        }
    }

    func openApproval() { SMAppService.openSystemSettingsLoginItems() }

    func select(_ selected: FanPreset) {
        guard canControl else { return }
        startupPreset = nil
        busy = true
        controlError = nil
        Task {
            defer { busy = false }
            await apply(selected)
        }
    }

    private func apply(_ selected: FanPreset) async {
        do {
            let status = try await helper.apply(selected, configuration: configuration(for: selected))
            preset = status.preset
            restoring = status.restoring
            controlError = status.message
            if status.preset == selected, !status.restoring, status.message == nil {
                defaults.set(selected.rawValue, forKey: "lastSelectedPreset")
            }
        } catch {
            connectionReady = false
            controlError = error.localizedDescription
        }
    }

    func configuration(for preset: FanPreset) -> PresetConfiguration {
        configurations[preset.rawValue] ?? .defaults(for: preset)
    }

    func save(_ configuration: PresetConfiguration, for selected: FanPreset) {
        guard !busy, !restoring else { return }
        do {
            try configuration.validate()
            var updated = configurations
            updated[selected.rawValue] = configuration
            defaults.set(try JSONEncoder().encode(updated), forKey: "presetConfigurations")
            configurations = updated
            if preset == selected && canControl { select(selected) }
        } catch { controlError = error.localizedDescription }
    }

    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            loginEnabled = SMAppService.mainApp.status == .enabled
        } catch { controlError = error.localizedDescription }
    }

    func removeService() {
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await helper.restore()
                helper.invalidate()
                try await service.unregister()
                connectionReady = false
                serviceState = .notRegistered
                preset = .standard
                controlError = nil
            } catch { controlError = error.localizedDescription }
        }
    }

    func prepareToQuit() async -> Bool {
        monitor?.cancel()
        monitor = nil
        do {
            if serviceState == .enabled && (preset != .standard || restoring) {
                _ = try await helper.restore()
            }
            helper.invalidate()
            return true
        } catch {
            controlError = String(format: String(localized: "Could not confirm automatic mode: %@"), String(localized: String.LocalizationValue(error.localizedDescription)))
            start()
            return false
        }
    }
}
