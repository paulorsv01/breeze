import BreezeCore
import SwiftUI

struct SettingsView: View {
    let store: FanStore

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { store.loginEnabled }, set: { _ in store.toggleLogin() }))
                Text("Breeze follows your preferred language in macOS: English, Spanish or Portuguese.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach([FanPreset.performance, .performancePlus]) { preset in
                PresetSettingsView(store: store, preset: preset)
            }
            Section("Fan control") {
                Text("Automatic mode is managed by macOS. Custom presets respect hardware limits and reach maximum speed if temperature readings are unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.serviceState == .enabled {
                    Button("Disable fan control", role: .destructive) { store.removeService() }
                        .disabled(store.busy || store.restoring)
                }
                if let error = store.controlError {
                    Text(String(localized: String.LocalizationValue(error))).foregroundStyle(.orange).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 560)
        .tint(Color.accentColor)
    }
}

private struct PresetSettingsView: View {
    let store: FanStore
    let preset: FanPreset

    private var configuration: PresetConfiguration { store.configuration(for: preset) }

    private func binding(_ keyPath: WritableKeyPath<PresetConfiguration, Double>) -> Binding<Double> {
        Binding(get: { configuration[keyPath: keyPath] }, set: { value in
            var updated = configuration
            updated[keyPath: keyPath] = value
            store.save(updated, for: preset)
        })
    }

    var body: some View {
        Section {
            Stepper(value: binding(\.minimumFraction), in: 0.3...1, step: 0.05) {
                LabeledContent("Minimum speed", value: configuration.minimumFraction.formatted(.percent.precision(.fractionLength(0))))
            }
            Stepper(value: binding(\.startTemperature), in: 30...min(65, configuration.fullTemperature - 5), step: 5) {
                LabeledContent("Start increasing at", value: "\(Int(configuration.startTemperature)) °C")
            }
            Stepper(value: binding(\.fullTemperature), in: max(50, configuration.startTemperature + 5)...85, step: 5) {
                LabeledContent("Maximum speed at", value: "\(Int(configuration.fullTemperature)) °C")
            }
            Button("Restore defaults") { store.save(.defaults(for: preset), for: preset) }
        } header: {
            Text(preset.title)
        }
        .disabled(store.busy || store.restoring)
    }
}
