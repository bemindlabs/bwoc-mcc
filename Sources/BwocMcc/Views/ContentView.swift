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

    private let refreshInterval: TimeInterval = 5

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
            Divider()
            HStack {
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                Spacer()
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

    private func openDetail(_ agent: Agent) {
        openWindow(id: "agent-detail", value: agent.id)
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
        Task { await runAction(action, for: agent) }
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
            snapshot = try await BwocCli.shared.list()
            lastError = nil
        } catch {
            lastError = "bwoc list failed: \(error.localizedDescription)"
        }
        // Sessions are supplementary — a failure here shouldn't blank the fleet.
        if let fresh = try? await BwocCli.shared.sessions() {
            sessions = fresh
        }
        if let ws = snapshot?.workspace {
            scrum = ScrumReader.read(workspace: ws)
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
    var onOpenDetail: () -> Void = {}
    let onAction: (AgentAction) -> Void

    @State private var expanded = false
    @State private var messages: [InboxMessage] = []
    @State private var loadingInbox = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
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
                inboxBadge
                actions
            }
            if expanded {
                inboxPreview
            }
        }
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
            actionButton(.chat, help: "Open chat in Terminal")
            if agent.running {
                actionButton(.stop, help: "Stop agent")
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
        guard expanded, messages.isEmpty else { return }
        loadingInbox = true
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
