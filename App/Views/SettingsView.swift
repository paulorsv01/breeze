import BreezeCore
import SwiftUI

struct SettingsView: View {
    let store: FanStore
    let onClose: () -> Void
    @State private var selected: FanPreset
    @State private var drafts: [FanPreset: PresetConfiguration]
    @State private var confirmingDiscard = false

    init(store: FanStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _selected = State(initialValue: store.preset == .standard ? .performance : store.preset)
        _drafts = State(initialValue: Dictionary(uniqueKeysWithValues: [FanPreset.performance, .performancePlus].map {
            ($0, store.configuration(for: $0))
        }))
    }

    private var configuration: PresetConfiguration {
        drafts[selected] ?? store.configuration(for: selected)
    }

    private var hasChanges: Bool {
        drafts.contains { $0.value != store.configuration(for: $0.key) }
    }

    private func binding(_ keyPath: WritableKeyPath<PresetConfiguration, Double>) -> Binding<Double> {
        Binding(get: { configuration[keyPath: keyPath] }, set: { value in
            var updated = configuration
            updated[keyPath: keyPath] = value
            drafts[selected] = updated
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    if hasChanges { confirmingDiscard = true }
                    else { onClose() }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Text("Settings").font(.headline)
            }
            .padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Customize your presets").font(.headline)
                        Text("Adjust the curve below. Changes apply when you save.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Preset", selection: $selected) {
                            ForEach([FanPreset.performance, .performancePlus]) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    PresetCurvePreview(configuration: configuration)

                    VStack(spacing: 18) {
                        PresetLimitControl(
                            title: String(localized: "Minimum speed"),
                            value: binding(\.minimumFraction), range: 0.3...1, step: 0.05,
                            valueLabel: configuration.minimumFraction.formatted(.percent.precision(.fractionLength(0)))
                        )
                        if configuration.minimumFraction < 1 {
                            Divider()
                            PresetLimitControl(
                                title: String(localized: "Start increasing at"),
                                value: binding(\.startTemperature),
                                range: 30...min(65, configuration.fullTemperature - 5), step: 1,
                                valueLabel: "\(Int(configuration.startTemperature)) °C"
                            )
                            PresetLimitControl(
                                title: String(localized: "Maximum speed at"),
                                value: binding(\.fullTemperature),
                                range: max(50, configuration.startTemperature + 5)...85, step: 1,
                                valueLabel: "\(Int(configuration.fullTemperature)) °C"
                            )
                            Divider()
                            PresetLimitControl(
                                title: String(localized: "Cooling margin"),
                                value: binding(\.hysteresis), range: 0...10, step: 1,
                                valueLabel: configuration.hysteresis == 0 ? String(localized: "Off") : "\(Int(configuration.hysteresis)) °C"
                            )
                            Text("Speed increases immediately as the Mac warms up. Small temperature drops hold the current speed; cooling beyond this margin gradually slows the fans.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("At 100%, this preset always runs at maximum speed. Lower the minimum to use a temperature curve.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: 12))

                    Button("Restore this preset") { drafts[selected] = .defaults(for: selected) }
                        .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                        .font(.caption)

                    Divider()
                    Toggle("Open at login", isOn: Binding(get: { store.loginEnabled }, set: store.setLoginEnabled))
                        .toggleStyle(.switch).controlSize(.small)
                    if store.serviceState == .enabled {
                        Button("Disable fan control", role: .destructive) { store.removeService() }
                            .disabled(store.busy || store.restoring)
                    }
                    Text("Automatic mode stays with macOS. Presets always respect each fan’s limits.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = store.controlError {
                        Text(String(localized: String.LocalizationValue(error)))
                            .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
                }
                .padding(18)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            HStack {
                Text(hasChanges ? String(localized: "Unsaved changes") : String(localized: "Presets saved"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button("Save presets") { store.save(drafts) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasChanges || store.busy || store.restoring)
            }
            .padding(16)
        }
        .frame(height: 570)
        .confirmationDialog("Discard unsaved preset changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive, action: onClose)
            Button("Keep editing", role: .cancel) {}
        }
    }
}
