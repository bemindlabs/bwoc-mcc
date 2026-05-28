import SwiftUI
import AppKit
import BwocMccCore

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 5
    @AppStorage(BwocCli.binaryDefaultsKey) private var binaryOverride: String = ""
    @AppStorage(TerminalApp.defaultsKey) private var terminalApp: String = TerminalApp.terminal.rawValue

    @State private var workspace: String = ""
    @State private var resolvedBinary: String = ""

    var body: some View {
        Form {
            Section("Refresh") {
                Stepper("Every \(Int(refreshInterval)) seconds", value: $refreshInterval, in: 2...60, step: 1)
            }

            Section("Workspace") {
                HStack {
                    Text(workspace.isEmpty ? "auto-detect (cwd)" : workspace)
                        .font(.callout)
                        .foregroundStyle(workspace.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseWorkspace() }
                }
                Text("Passed as --workspace to every bwoc command.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Terminal") {
                Picker("Open actions in", selection: $terminalApp) {
                    ForEach(TerminalApp.allCases, id: \.rawValue) { app in
                        Text(app.rawValue).tag(app.rawValue)
                    }
                }
                Text("Where spawn / chat / supervise / inbox-watch open.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("bwoc binary") {
                Text("Resolved: \(resolvedBinary.isEmpty ? "not found on PATH" : resolvedBinary)")
                    .font(.callout)
                    .foregroundStyle(resolvedBinary.isEmpty ? .red : .secondary)
                    .lineLimit(1).truncationMode(.middle)
                TextField("override path (optional)", text: $binaryOverride)
                Text("Leave blank to auto-detect. Applies on relaunch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 340)
        .task {
            workspace = await BwocCli.shared.currentWorkspace() ?? ""
            resolvedBinary = await BwocCli.shared.binaryPath() ?? ""
        }
    }

    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Workspace"
        panel.message = "Select your BWOC workspace root (contains .bwoc/workspace.toml)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace = url.path
        Task { await BwocCli.shared.setWorkspace(url.path) }
    }
}
