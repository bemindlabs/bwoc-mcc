import Foundation
import BwocMccCore

/// Tracks live stream child processes so they can be killed when the app quits.
/// macOS does not reap a parent's children automatically, and
/// `applicationWillTerminate` may run before SwiftUI tears down the detail
/// windows — without this, `bwoc inbox --watch` / `log -f` would survive as
/// the orphan sessions the fleet view warns about. Lock-guarded so it is safe
/// to call from `deinit` and the terminate hook off the main actor.
final class StreamRegistry: @unchecked Sendable {
    static let shared = StreamRegistry()
    private let lock = NSLock()
    private var table: [ObjectIdentifier: Process] = [:]

    func register(_ p: Process) {
        lock.lock(); defer { lock.unlock() }
        table[ObjectIdentifier(p)] = p
    }

    func unregister(_ p: Process) {
        lock.lock(); defer { lock.unlock() }
        table[ObjectIdentifier(p)] = nil
    }

    func terminateAll() {
        lock.lock()
        let procs = Array(table.values)
        table.removeAll()
        lock.unlock()
        for p in procs where p.isRunning { p.terminate() }
    }
}

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
            Task { @MainActor [weak self] in self?.finish() }
        }

        do {
            try proc.run()
            process = proc
            running = true
            StreamRegistry.shared.register(proc)
        } catch {
            lines = ["failed to start `bwoc \(argv.joined(separator: " "))`: \(error.localizedDescription)"]
        }
    }

    func stop() {
        if let process {
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            StreamRegistry.shared.unregister(process)
        }
        process = nil
        running = false
    }

    private func ingest(_ chunk: String) {
        appendLines(buffer.append(chunk))
    }

    /// Child exited: surface any buffered text that never got its trailing
    /// newline (e.g. the last `log -f` line before the agent stopped), then
    /// mark the stream idle.
    private func finish() {
        if let tail = buffer.flush() { appendLines([tail]) }
        running = false
    }

    private func appendLines(_ fresh: [String]) {
        guard !fresh.isEmpty else { return }
        lines.append(contentsOf: fresh)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    deinit {
        if let process {
            if process.isRunning { process.terminate() }
            StreamRegistry.shared.unregister(process)
        }
    }
}
