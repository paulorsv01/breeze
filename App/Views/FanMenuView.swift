import AppKit
import BreezeCore
import SwiftUI

struct FanMenuView: View {
    let store: FanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image("MenuBarIcon").renderingMode(.template)
                        .foregroundStyle(Color.accentColor)
                    Text("Breeze").font(.system(size: 15, weight: .semibold))
                }
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                else {
                    Text(store.restoring ? String(localized: "Restoring…") : (store.connectionReady ? store.preset.title : String(localized: "Monitoring")))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: .capsule)
                }
            }

            telemetry

            VStack(alignment: .leading, spacing: 8) {
                Text("Presets")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(FanPreset.allCases) { preset in
                    PresetButton(preset: preset, configuration: store.configuration(for: preset), selected: store.connectionReady && store.preset == preset) { store.select(preset) }
                        .disabled(!store.canControl || (preset != .standard && store.snapshot == nil))
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

            serviceControls

            Divider()
            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
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
        .frame(width: 360)
        .tint(Color.accentColor)
    }

    private var telemetry: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(store.rpmLabel).font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit()
                Text("RPM").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if let temperature = store.snapshot?.temperature {
                    Label("\(Int(temperature.rounded())) °C", systemImage: "thermometer.medium")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .help("Highest available CPU or GPU sensor temperature")
                }
            }
            if let snapshot = store.snapshot {
                ForEach(snapshot.fans) { fan in
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: min(fan.rpm / fan.limits.maximum, 1))
                            .tint(Color.accentColor)
                        HStack {
                            Text(snapshot.fans.count == 1 ? String(localized: "Fan") : String(format: String(localized: "Fan %d"), fan.id + 1))
                            Spacer()
                            Text("\(Int(fan.rpm)) / \(Int(fan.limits.maximum)) RPM").monospacedDigit()
                        }
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(store.sensorError == nil ? String(localized: "Reading fan…") : String(localized: "Reading unavailable"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var serviceControls: some View {
        switch store.serviceState {
        case .notRegistered:
            VStack(alignment: .leading, spacing: 8) {
                Text("Enable the service to switch presets. macOS will ask for authorization.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Enable fan control") { store.activateService() }
                    .buttonStyle(.borderedProminent).controlSize(.regular)
                    .disabled(store.busy || store.snapshot == nil)
            }
        case .needsApproval:
            VStack(alignment: .leading, spacing: 8) {
                Text("Allow Breeze in Login Items & Extensions in System Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open macOS authorization") { store.openApproval() }.buttonStyle(.bordered)
            }
        case .enabled:
            Text(store.connectionReady ? String(localized: "Quitting returns control to macOS.") : String(localized: "Connecting to service…"))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        case .unavailable:
            Text("Service files are missing. Reinstall the app.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
