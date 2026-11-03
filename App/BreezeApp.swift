import AppKit
import BreezeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: FanStore?
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        guard let store else { return .terminateNow }
        guard !store.busy else { return .terminateCancel }
        terminating = true
        Task {
            let ready = await store.prepareToQuit()
            terminating = false
            NSApp.reply(toApplicationShouldTerminate: ready)
        }
        return .terminateLater
    }
}

@main
struct BreezeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = FanStore()

    var body: some Scene {
        MenuBarExtra {
            FanMenuView(store: store)
                .onAppear { delegate.store = store }
        } label: {
            Label {
                Text("Breeze")
            } icon: {
                Image("MenuBarIcon").renderingMode(.template)
            }
                .help("Breeze · \(store.preset.title) · \(store.rpmLabel) RPM")
                .task {
                    delegate.store = store
                    store.start()
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
