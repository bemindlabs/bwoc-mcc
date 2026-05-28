import SwiftUI
import AppKit

@main
struct BwocMccApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("BWOC", systemImage: "person.3.sequence") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar–only agent: keep it out of the Dock and the ⌘-Tab switcher.
        // (Equivalent to LSUIElement, set at runtime since a bare SwiftPM
        // executable has no Info.plist to carry it.)
        NSApp.setActivationPolicy(.accessory)
    }
}
