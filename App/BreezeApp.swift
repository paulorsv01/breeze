import AppKit
import BreezeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = FanStore()
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
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

    var body: some Scene {
        MenuBarExtra {
            FanMenuView(store: delegate.store)
        } label: {
            BreezeMenuLabel(store: delegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}
