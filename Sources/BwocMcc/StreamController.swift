import Foundation
import BwocMccCore

/// Owns a long-running `bwoc` child process and republishes its stdout as
/// lines. Lifecycle is explicit: `start` spawns, `stop` terminates — the view
/// must call `stop` on disappear so the child never outlives the window (which
/// would surface as an orphan in the Sessions view).
@MainActor
final class StreamController: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published private(set) var running = false

    private var process: Process?
    private var buffer = LineBuffer()
    private let maxLines = 2000

    func start(kind: StreamKind, agent: String) async {
        stop()
        lines = []
        guard let path = await BwocCli.shared.binaryPath() else {
            lines = ["bwoc binary not found on PATH"]
            return
        }
        let argv = await BwocCli.shared.streamArgv(kind, agent: agent)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = argv
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.ingest(chunk) }
        }
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.running = false }
        }

        do {
            try proc.run()
            process = proc
            running = true
        } catch {
            lines = ["failed to start `bwoc \(argv.joined(separator: " "))`: \(error.localizedDescription)"]
        }
    }

    func stop() {
        if let process {
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }
        process = nil
        running = false
    }

    private func ingest(_ chunk: String) {
        let fresh = buffer.append(chunk)
        guard !fresh.isEmpty else { return }
        lines.append(contentsOf: fresh)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    deinit {
        process?.terminate()
    }
}
