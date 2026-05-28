import SwiftUI
import BwocMccCore

struct AgentDetailWindow: View {
    let agentId: String
    @State private var kind: StreamKind = .inbox

    var body: some View {
        VStack(spacing: 0) {
            Picker("Stream", selection: $kind) {
                ForEach(StreamKind.allCases, id: \.self) { k in
                    Text(k.title).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            // Recreate the stream view per tab so switching cleanly stops the
            // old child process and starts the new one.
            StreamView(kind: kind, agent: agentId)
                .id(kind)
        }
        .frame(minWidth: 480, minHeight: 320)
        .navigationTitle(agentId)
    }
}

private struct StreamView: View {
    let kind: StreamKind
    let agent: String
    @StateObject private var controller = StreamController()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(controller.lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(8)
            }
            .onChange(of: controller.lines.count) { _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                statusPill.padding(8)
            }
        }
        .task { await controller.start(kind: kind, agent: agent) }
        .onDisappear { controller.stop() }
    }

    private let bottomID = "bottom"

    @ViewBuilder
    private var statusPill: some View {
        if controller.running {
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("streaming").font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
        } else {
            // Child exited (error / agent stopped / EOF) — offer a restart
            // instead of forcing a tab close+reopen.
            Button {
                Task { await controller.start(kind: kind, agent: agent) }
            } label: {
                Label("Reconnect", systemImage: "arrow.clockwise").font(.caption2)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
        }
    }
}
