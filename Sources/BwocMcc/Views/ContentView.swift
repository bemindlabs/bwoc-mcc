import SwiftUI
import BwocMccCore

struct ContentView: View {
    @State private var snapshot: FleetSnapshot? = nil
    @State private var lastError: String? = nil
    @State private var isRefreshing = false

    private let refreshInterval: TimeInterval = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if let snapshot {
                ForEach(snapshot.agents) { agent in
                    AgentRow(agent: agent)
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

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            snapshot = try await BwocCli.shared.list()
            lastError = nil
        } catch {
            lastError = "bwoc list failed: \(error.localizedDescription)"
        }
    }
}

private struct AgentRow: View {
    let agent: Agent

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
        }
    }
}
