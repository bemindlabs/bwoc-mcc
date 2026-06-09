import SwiftUI
import BwocMccCore

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow

    @State private var snapshot: FleetSnapshot? = nil
    @State private var sessions: [Session] = []
    @State private var scrum: ScrumState? = nil
    @State private var lastError: String? = nil
    @State private var isRefreshing = false
    @State private var pendingStop: Agent? = nil
    /// Team-chat selection mode: rows show a checkbox and the footer offers
    /// "Open team chat (N)", which launches ONE bwoc-chat window for all picked
    /// agents (`bwoc-chat a b c`).
    @State private var teamMode = false
    @State private var teamSelection: Set<String> = []

    @AppStorage("refreshInterval") private var refreshInterval: Double = 5

    @ObservedObject private var mascots = MascotManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let scrum {
                ScrumStrip(state: scrum)
            }
            Divider()
            if let snapshot {
                ForEach(snapshot.agents) { agent in
                    AgentRow(
                        agent: agent,
                        blocked: scrum?.blockedAgents.contains(agent.id) ?? false,
                        teamMode: teamMode,
                        selected: teamSelection.contains(agent.id),
                        onToggleSelect: { toggleTeam(agent) },
                        onOpenDetail: { openDetail(agent) }
                    ) { action in
                        handle(action, for: agent)
                    }
                }
                if !sessions.isEmpty {
                    Divider()
                    SessionsSection(sessions: sessions)
                }
                Divider()
                Text(snapshot.workspace)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let lastError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Set workspace…") { chooseWorkspace() }
                        .controlSize(.small)
                }
            } else {
                ProgressView().controlSize(.small)
            }
            if let lastError, snapshot != nil {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            if teamMode {
                teamBar
            }
            Divider()
            HStack {
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                Spacer()
                Button {
                    mascots.toggleDesktopMascot()
                } label: {
                    Image(systemName: mascots.desktopMascotShown ? "sparkles" : "sparkle")
                }
                .help(mascots.desktopMascotShown
                    ? "Dismiss the desktop mascot"
                    : "Spawn a mascot that wanders the screen (drag to move · double-click to dismiss)")
                Button {
                    teamMode.toggle()
                    if !teamMode { teamSelection.removeAll() }
                } label: {
                    Image(systemName: teamMode ? "person.2.fill" : "person.2")
                }
                .help(teamMode ? "Exit team-chat selection" : "Team chat — pick agents for one shared window")
                Button {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button(action: { Task { await refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            }
        }
        .padding(12)
        .frame(width: 360)
        .confirmationDialog(
            "Stop \(pendingStop?.id ?? "")?",
            isPresented: Binding(
                get: { pendingStop != nil },
                set: { if !$0 { pendingStop = nil } }
            ),
            presenting: pendingStop
        ) { agent in
            Button("Stop — \(agent.inboxCount) unread message\(agent.inboxCount == 1 ? "" : "s")", role: .destructive) {
                let target = agent
                pendingStop = nil
                Task { await runAction(.stop, for: target) }
            }
            Button("Cancel", role: .cancel) { pendingStop = nil }
        } message: { agent in
            Text("\(agent.id) has \(agent.inboxCount) unread message\(agent.inboxCount == 1 ? "" : "s"). Stopping now leaves them undrained.")
        }
        .task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(refreshInterval * 1_000_000_000))
                await refresh()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("BWOC Fleet")
                .font(.headline)
            Spacer()
            if let snapshot {
                Text("\(snapshot.agents.count) agents")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Bottom bar shown in team-chat mode: count + Cancel + Open.
    private var teamBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(teamSelection.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                teamMode = false
                teamSelection.removeAll()
            }
            .controlSize(.small)
            Button {
                openTeamChat()
            } label: {
                Label("Open team chat", systemImage: "bubble.left.and.bubble.right")
            }
            .controlSize(.small)
            .disabled(teamSelection.count < 2)
            .help("Open one bwoc-chat window for the selected agents")
        }
    }

    private func toggleTeam(_ agent: Agent) {
        // Only harness-renderable agents can join a bwoc-chat window; ignore taps
        // on the rest (their checkbox is disabled anyway).
        guard agent.supportsChatWindow else { return }
        if teamSelection.contains(agent.id) {
            teamSelection.remove(agent.id)
        } else {
            teamSelection.insert(agent.id)
        }
    }

    /// Launch ONE bwoc-chat window for every selected agent (`bwoc-chat a b c`).
    private func openTeamChat() {
        let agents = snapshot?.agents.filter { teamSelection.contains($0.id) } ?? []
        guard agents.count >= 2 else { return }
        Task {
            do {
                try await BwocCli.shared.openChatWindow(agents: agents)
                lastError = nil
                teamMode = false
                teamSelection.removeAll()
            } catch {
                lastError = "team chat failed: \(error.localizedDescription)"
            }
        }
    }

    private func openDetail(_ agent: Agent) {
        // Reuse an already-open detail window (titled with the agent id) rather
        // than spawning a duplicate with its own stream.
        if let existing = NSApp.windows.first(where: { $0.title == agent.id }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "agent-detail", value: agent.id)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Fallback when `bwoc list` can't find the workspace (e.g. bundled .app
    /// with cwd = "/"): let the operator pin the root, persist it, and retry.
    private func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Workspace"
        panel.message = "Select your BWOC workspace root (the folder containing .bwoc/workspace.toml)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await BwocCli.shared.setWorkspace(url.path)
            await refresh()
        }
    }

    private func handle(_ action: AgentAction, for agent: Agent) {
        if action == .stop && agent.inboxCount > 0 {
            pendingStop = agent
            return
        }
        if action == .chat {
            Task { await openChat(for: agent) }
            return
        }
        Task { await runAction(action, for: agent) }
    }

    /// Prefer the native `bwoc-chat` window for harness-backed agents; fall back
    /// to `bwoc chat` in Terminal for vendor-CLI agents (which bwoc-chat can't
    /// render) or if bwoc-chat isn't installed / fails to launch.
    private func openChat(for agent: Agent) async {
        if agent.supportsChatWindow, await BwocCli.shared.chatBinaryPath() != nil {
            do {
                try await BwocCli.shared.openChatWindow(agents: [agent])
                lastError = nil
                return
            } catch {
                // Launch failed — fall through to the Terminal path below.
            }
        }
        await runAction(.chat, for: agent)
    }

    private func runAction(_ action: AgentAction, for agent: Agent) async {
        do {
            if action.isInteractive {
                try await BwocCli.shared.openInTerminal(action, agent: agent)
            } else {
                try await BwocCli.shared.perform(action, agent: agent)
                await refresh()
            }
            lastError = nil
        } catch {
            lastError = "\(action.rawValue) \(agent.id) failed: \(error.localizedDescription)"
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let snap = try await BwocCli.shared.list()
            snapshot = snap
            mascots.updateFleet(snap)   // keep agent mascots' running-state live
            lastError = nil
        } catch {
            lastError = "bwoc list failed: \(error.localizedDescription)"
        }
        // Sessions are supplementary — a failure here shouldn't blank the fleet.
        if let fresh = try? await BwocCli.shared.sessions() {
            sessions = fresh
        }
        if let ws = snapshot?.workspace {
            // Read .scrum/ off the main actor — it's blocking file IO.
            scrum = await Task.detached { ScrumReader.read(workspace: ws) }.value
        }
    }
}

private struct ScrumStrip: View {
    let state: ScrumState

    private var daysText: String {
        guard let d = state.daysLeft else { return "" }
        if d < 0 { return "overdue" }
        if d == 0 { return "last day" }
        return "\(d)d left"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flag.checkered")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(state.sprintId)
                .font(.caption.bold())
            if !daysText.isEmpty {
                Text("· \(daysText)")
                    .font(.caption2)
                    .foregroundStyle((state.daysLeft ?? 1) <= 0 ? .orange : .secondary)
            }
            Spacer()
            Text("\(state.pointsDone)/\(state.pointsCommitted) pts")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct SessionsSection: View {
    let sessions: [Session]
    @State private var expanded = false

    private var bound: Int { sessions.filter { !$0.isOrphan }.count }
    private var orphans: Int { sessions.filter(\.isOrphan).count }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(sessions) { session in
                    HStack(spacing: 6) {
                        Image(systemName: session.isRunning ? "circle.fill" : "circle")
                            .font(.system(size: 7))
                            .foregroundStyle(session.isRunning ? .green : .secondary)
                        Text(session.agentId ?? "unbound")
                            .font(.system(.caption2, design: .monospaced))
                        Text("· \(session.backend) · pid \(session.pid)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(session.source)
                            .font(.caption2)
                            .foregroundStyle(session.isOrphan ? .orange : .secondary)
                    }
                }
            }
            .padding(.top, 2)
        } label: {
            HStack {
                Text("Sessions").font(.caption.bold())
                Spacer()
                Text("\(bound) bound\(orphans > 0 ? " · \(orphans) orphan" : "")")
                    .font(.caption2)
                    .foregroundStyle(orphans > 0 ? .orange : .secondary)
            }
        }
    }
}

private struct AgentRow: View {
    let agent: Agent
    var blocked: Bool = false
    var teamMode: Bool = false
    var selected: Bool = false
    var onToggleSelect: () -> Void = {}
    var onOpenDetail: () -> Void = {}
    let onAction: (AgentAction) -> Void

    @State private var expanded = false
    @State private var messages: [InboxMessage] = []
    @State private var loadingInbox = false
    @ObservedObject private var mascots = MascotManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if teamMode {
                    Button(action: onToggleSelect) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checkboxColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(!agent.supportsChatWindow)
                    .help(agent.supportsChatWindow
                        ? "Add to team chat"
                        : "\(agent.backend) backend can't render in a chat window")
                }
                Circle()
                    .fill(agent.running ? .green : .gray)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.id).font(.system(.body, design: .monospaced))
                    Text("\(agent.backend) · \(agent.status)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if blocked {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .help("Owns a story with an open blocker")
                }
                Spacer()
                // Per-agent actions collapse in team mode to keep the row focused
                // on selection.
                if !teamMode {
                    inboxBadge
                    actions
                }
            }
            if expanded {
                inboxPreview
            }
        }
        .onChange(of: agent.inboxCount) { newCount in
            // Keep an open preview in sync with the 5s fleet refresh.
            guard expanded else { return }
            if newCount == 0 {
                expanded = false
                messages = []
            } else {
                reloadInbox()
            }
        }
    }

    private var checkboxColor: Color {
        guard agent.supportsChatWindow else { return Color.secondary.opacity(0.3) }
        return selected ? Color.accentColor : Color.secondary
    }

    @ViewBuilder
    private var inboxBadge: some View {
        if agent.inboxCount > 0 {
            Button(action: toggleInbox) {
                HStack(spacing: 3) {
                    Text("\(agent.inboxCount)")
                        .font(.caption.monospacedDigit())
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(.blue.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .help("Preview inbox")
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 2) {
            Button(action: onOpenDetail) {
                Image(systemName: "dot.radiowaves.left.and.right")
            }
            .buttonStyle(.borderless)
            .help("Stream inbox + log")
            Button(action: { mascots.toggleAgentMascot(agent.id) }) {
                Image(systemName: mascots.isShown(agent.id) ? "sparkles" : "sparkle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(mascots.isShown(agent.id) ? Color.pink : Color.secondary)
            .help(mascots.isShown(agent.id)
                ? "Recall \(agent.id)'s desktop mascot"
                : "Send \(agent.id) out as a desktop mascot")
            actionButton(.chat, help: agent.supportsChatWindow
                ? "Open native chat window (bwoc-chat)"
                : "Open chat in Terminal")
            if agent.running {
                actionButton(.stop, help: "Stop agent")
                actionButton(.supervise, help: "Supervise in Terminal (restart on crash)")
            } else {
                actionButton(.start, help: "Start agent")
                actionButton(.spawn, help: "Spawn in Terminal")
            }
        }
    }

    private func actionButton(_ action: AgentAction, help: String) -> some View {
        Button(action: { onAction(action) }) {
            Image(systemName: action.systemImage)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    @ViewBuilder
    private var inboxPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loadingInbox {
                ProgressView().controlSize(.small)
            } else if messages.isEmpty {
                Text("No messages").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(messages) { msg in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(msg.from).font(.caption2.bold())
                            Spacer()
                            Text(Self.age(msg.ts)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(msg.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Button {
                    Task { try? await BwocCli.shared.openInboxWatch(agent: agent.id) }
                } label: {
                    Label("Watch in Terminal", systemImage: "terminal")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.leading, 16)
    }

    private func toggleInbox() {
        expanded.toggle()
        if expanded { reloadInbox() }
    }

    private func reloadInbox() {
        loadingInbox = messages.isEmpty   // spinner only on the first fetch
        Task {
            defer { loadingInbox = false }
            if let snap = try? await BwocCli.shared.inbox(agent: agent.id, limit: 3) {
                messages = snap.messages
            }
        }
    }

    static func age(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: iso) else { return iso }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
