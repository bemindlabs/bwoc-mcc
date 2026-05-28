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

        WindowGroup(id: "agent-detail", for: String.self) { $agentId in
            if let agentId {
                AgentDetailWindow(agentId: agentId)
            }
        }
        .defaultSize(width: 620, height: 460)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar–only agent: keep it out of the Dock and the ⌘-Tab switcher.
        // (Equivalent to LSUIElement, set at runtime since a bare SwiftPM
        // executable has no Info.plist to carry it.)
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Reap any live stream children so a Quit with open detail windows
        // doesn't leave orphaned `bwoc inbox --watch` / `log -f` processes.
        StreamRegistry.shared.terminateAll()
    }
}
