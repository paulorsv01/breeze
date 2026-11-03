import SwiftUI

struct FanHeaderView: View {
    let store: FanStore

    var body: some View {
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
    }
}
