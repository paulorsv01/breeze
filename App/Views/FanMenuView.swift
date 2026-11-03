import SwiftUI

struct FanMenuView: View {
    let store: FanStore
    @State private var showingSettings = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(store: store) { showingSettings = false }
            } else {
                FanDashboardView(store: store) { showingSettings = true }
            }
        }
        .frame(width: 400)
        .tint(Color.accentColor)
    }
}
