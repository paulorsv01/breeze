import AppKit
import BreezeCore
import SwiftUI

struct FanDashboardView: View {
    let store: FanStore
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FanHeaderView(store: store)

            FanTelemetryView(store: store)

            VStack(alignment: .leading, spacing: 8) {
                Text("Presets")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(FanPreset.allCases) { preset in
                    PresetButton(preset: preset, configuration: store.configuration(for: preset), selected: store.connectionReady && store.preset == preset) { store.select(preset) }
                        .disabled(!store.canControl || (preset != .standard && store.sensorError != nil))
                }
            }

            if let message = store.error {
                Label {
                    Text(String(localized: String.LocalizationValue(message))).textSelection(.enabled)
                } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            FanServiceControlsView(store: store)

            Divider()
            HStack {
                Button(action: onSettings) {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Settings")
                .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("q")
                    .disabled(store.busy)
            }
            .font(.system(size: 12))
        }
        .padding(20)
    }

}
