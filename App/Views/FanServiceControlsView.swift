import SwiftUI

struct FanServiceControlsView: View {
    let store: FanStore

    var body: some View {
        switch store.serviceState {
        case .checking:
            Text("Connecting to service…")
                .font(.caption).foregroundStyle(.secondary)
        case .notRegistered:
            if store.busy {
                Text("Connecting to service…")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enable the service to switch presets. macOS will ask for authorization.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Enable fan control") { store.activateService() }
                        .buttonStyle(.borderedProminent).controlSize(.regular)
                        .disabled(store.busy || store.snapshot == nil)
                }
            }
        case .needsApproval:
            VStack(alignment: .leading, spacing: 8) {
                Text("Allow Breeze in Login Items & Extensions in System Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open macOS authorization") { store.openApproval() }.buttonStyle(.bordered)
            }
        case .enabled:
            Text(store.updatingService ? String(localized: "Updating fan control…") : (store.connectionReady ? String(localized: "Quitting returns control to macOS.") : String(localized: "Connecting to service…")))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        case .unavailable:
            Text("Service files are missing. Reinstall the app.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
