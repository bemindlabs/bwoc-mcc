import SwiftUI
import AppKit

@main
struct BwocMccApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "agent-detail", for: String.self) { $agentId in
            if let agentId {
                AgentDetailWindow(agentId: agentId)
            }
        }
        .defaultSize(width: 620, height: 460)

        // A plain Window (not the SwiftUI `Settings` scene) — an `.accessory`
        // app has no main menu, so the Settings scene can't be summoned. This
        // opens reliably via openWindow + NSApp.activate, same as agent-detail.
        Window("BWOC Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 400, height: 340)
        .windowResizability(.contentSize)
    }
}

/// The menu-bar icon: the lotus, with an orange dot when the harness has raised
/// pending approval requests (observes the shared [`ApprovalModel`]).
private struct MenuBarLabel: View {
    @ObservedObject private var approvals = ApprovalModel.shared

    var body: some View {
        Image(nsImage: LotusIcon.image)
            .overlay(alignment: .topTrailing) {
                if !approvals.pending.isEmpty {
                    Circle()
                        .fill(.orange)
                        .frame(width: 6, height: 6)
                }
            }
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
        // Tear down any desktop mascots so their wander timers stop with the app.
        MascotManager.shared.dismissAll()
    }
}
