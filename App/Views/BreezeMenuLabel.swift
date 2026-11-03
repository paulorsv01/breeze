import SwiftUI

struct BreezeMenuLabel: View {
    let store: FanStore

    var body: some View {
        Label {
            Text("Breeze")
        } icon: {
            Image("MenuBarIcon").renderingMode(.template)
        }
        .help("Breeze · \(store.preset.title) · \(store.rpmLabel) RPM")
    }
}
