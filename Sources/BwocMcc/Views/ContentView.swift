import SwiftUI
import BwocMccCore

struct ContentView: View {
    @State private var snapshot: FleetSnapshot? = nil
    @State private var sessions: [Session] = []
    @State private var lastError: String? = nil
    @State private var isRefreshing = false
    @State private var pendingStop: Agent? = nil

    private let refreshInterval: TimeInterval = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if let snapshot {
                ForEach(snapshot.agents) { agent in
                    AgentRow(agent: agent) { action in
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
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
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
                try await BwocCli.shared.openInTerminal(action, agent: agent.id)
            } else {
                try await BwocCli.shared.perform(action, agent: agent.id)
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
    let onAction: (AgentAction) -> Void

    var body: some View {
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
            Spacer()
            if agent.inboxCount > 0 {
                Text("\(agent.inboxCount)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.blue.opacity(0.2)))
            }
            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 2) {
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
}
