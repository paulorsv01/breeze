import AppKit
import BreezeCore
import Observation
import ServiceManagement

@MainActor @Observable
final class FanStore {
    enum ServiceState { case checking, notRegistered, needsApproval, enabled, unavailable }

    private(set) var snapshot: FanSnapshot?
    private(set) var preset: FanPreset = .standard
    private(set) var serviceState: ServiceState = .checking
    private(set) var busy = false
    private(set) var connectionReady = false
    private(set) var restoring = false
    private(set) var sensorError: String?
    private(set) var controlError: String?
    private(set) var loginEnabled = false
    private let reader = SensorReader()
    private let helper = HelperClient()
    private let updater = HelperUpdater()
    private var expectedInstallation: HelperInstallation?
    private var serviceVerified = false
    private var attemptedRegistration = false
    private var controlRevision = 0
    private(set) var updatingService = false
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
        if defaults.object(forKey: "fanControlEnabled") == nil, serviceState == .enabled {
            defaults.set(true, forKey: "fanControlEnabled")
        }
        if serviceState == .notRegistered, defaults.bool(forKey: "fanControlEnabled"),
           !attemptedRegistration, !busy {
            activateService()
            return
        }
        do { snapshot = try await reader.snapshot(); sensorError = nil }
        catch { snapshot = nil; sensorError = error.localizedDescription }
        guard serviceState == .enabled else {
            connectionReady = false
            helper.invalidate()
            return
        }
        guard !busy else { return }
        let revision = controlRevision
        do {
            let status: ControlStatus?
            if serviceVerified {
                status = try await helper.heartbeat()
            } else {
                busy = true
                defer { busy = false }
                status = try await ensureCurrentService()
            }
            guard let status, !busy, !Task.isCancelled, revision == controlRevision else { return }
            guard status.installation == expectedInstallation else {
                throw FanError.unavailable("The service update could not be confirmed. Reopen Breeze to retry.")
            }
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
            guard !busy, !Task.isCancelled, revision == controlRevision else { return }
            connectionReady = false
            controlError = error.localizedDescription
        }
    }

    private func ensureCurrentService() async throws -> ControlStatus? {
        if expectedInstallation == nil {
            expectedInstallation = try HelperInstallation(bundleURL: Bundle.main.bundleURL)
        }
        guard let expectedInstallation else { return nil }
        let current = try? await helper.heartbeat(timeout: 2)
        updatingService = current?.installation != expectedInstallation
        defer { updatingService = false }
        let status = try await updater.reconcile(
            expected: expectedInstallation, current: current,
            restore: { try await self.helper.restore() },
            register: {
                self.helper.invalidate()
                try await self.service.unregister()
                do { try self.service.register() }
                catch {
                    self.refreshServiceState()
                    if self.serviceState == .needsApproval { return false }
                    throw error
                }
                self.refreshServiceState()
                return self.serviceState == .enabled
            },
            probe: { try await self.helper.heartbeat(timeout: 2) },
            wait: { try await Task.sleep(for: .seconds($0)) }
        )
        serviceVerified = status != nil
        return status
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
        guard !busy else { return }
        attemptedRegistration = true
        defaults.set(true, forKey: "fanControlEnabled")
        controlRevision += 1
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
        controlRevision += 1
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

    @discardableResult
    func save(_ presets: [FanPreset: PresetConfiguration]) -> Bool {
        guard !busy, !restoring else { return false }
        do {
            var updated = configurations
            for (preset, configuration) in presets where preset != .standard {
                try configuration.validate()
                updated[preset.rawValue] = configuration
            }
            let activeChanged = (updated[preset.rawValue] ?? .defaults(for: preset)) != configuration(for: preset)
            defaults.set(try JSONEncoder().encode(updated), forKey: "presetConfigurations")
            configurations = updated
            if activeChanged && canControl { select(preset) }
            return true
        } catch {
            controlError = error.localizedDescription
            return false
        }
    }

    func setLoginEnabled(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
        } catch { controlError = error.localizedDescription }
    }

    func removeService() {
        guard !busy else { return }
        controlRevision += 1
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await helper.restore()
                helper.invalidate()
                try await service.unregister()
                defaults.set(false, forKey: "fanControlEnabled")
                connectionReady = false
                serviceVerified = false
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
