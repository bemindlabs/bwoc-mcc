import Foundation

public enum BwocCliError: Error, CustomStringConvertible {
    case binaryNotFound
    case nonZeroExit(code: Int32, stderr: String)
    case decodeFailed(String)
    case timedOut(seconds: TimeInterval)

    public var description: String {
        switch self {
        case .binaryNotFound:
            return "`bwoc` binary not found on PATH"
        case .nonZeroExit(let code, let stderr):
            return "bwoc exited \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .decodeFailed(let msg):
            return "decode failed: \(msg)"
        case .timedOut(let seconds):
            return "bwoc timed out after \(Int(seconds))s"
        }
    }
}

/// Thread-safe one-shot flag used to tell `capture()` that its timeout fired
/// (so it can distinguish a timeout-kill from a normal non-zero exit).
private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

public enum AgentAction: String, Sendable, CaseIterable {
    case spawn
    case chat
    case start
    case stop
    case supervise

    /// Interactive flows need a real TTY, so they launch in Terminal.app
    /// rather than running inside the app's process. `supervise` is a
    /// foreground daemon loop — running it via the in-process capture() would
    /// block the actor forever, so it must be interactive too.
    public var isInteractive: Bool {
        switch self {
        case .spawn, .chat, .supervise: return true
        case .start, .stop: return false
        }
    }

    public var systemImage: String {
        switch self {
        case .spawn: return "play.circle"
        case .chat: return "bubble.left"
        case .start: return "power"
        case .stop: return "stop.circle"
        case .supervise: return "eye"
        }
    }

    /// Argument vector for this action. `spawn` targets the agent directory
    /// by `--path`; the others take the agent name plus an explicit
    /// `--workspace` so the command resolves correctly even when launched from
    /// outside the workspace tree (e.g. Terminal opening at $HOME).
    public func argv(agent: Agent, workspace: String?) -> [String] {
        switch self {
        case .spawn:
            let dir = workspace.map { "\($0)/\(agent.path)" } ?? agent.path
            return ["spawn", "--path", dir]
        case .chat, .start, .stop, .supervise:
            return [rawValue, agent.id] + Self.workspaceFlag(workspace)
        }
    }

    static func workspaceFlag(_ workspace: String?) -> [String] {
        workspace.map { ["--workspace", $0] } ?? []
    }
}

public actor BwocCli {
    public static let shared = BwocCli()

    private static let candidatePaths: [String] = [
        "/opt/homebrew/bin/bwoc",
        "/usr/local/bin/bwoc",
        NSString(string: "~/.local/bin/bwoc").expandingTildeInPath,
        NSString(string: "~/.cargo/bin/bwoc").expandingTildeInPath
    ]

    private let binaryURL: URL?

    /// Learned from the first successful `list()` and then passed as
    /// `--workspace` to every subsequent command, so actions resolve the right
    /// workspace even when the host process (or a spawned Terminal) has a cwd
    /// outside the workspace tree.
    private var cachedWorkspace: String? = nil

    static let workspaceDefaultsKey = "bwoc.workspacePath"
    public static let binaryDefaultsKey = "bwoc.binaryPath"

    public init() {
        // A user-set override (Settings) wins over the built-in candidates.
        let override = UserDefaults.standard.string(forKey: Self.binaryDefaultsKey)
            .flatMap { $0.isEmpty ? nil : $0 }
        let candidates = (override.map { [$0] } ?? []) + Self.candidatePaths
        self.binaryURL = candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        // Seed the workspace so the very first `list()` resolves even when cwd
        // is outside the tree (e.g. a double-clicked .app, cwd = "/"). Falls
        // back to ancestor-walk when neither source is set (dev / cwd inside).
        self.cachedWorkspace = ProcessInfo.processInfo.environment["BWOC_WORKSPACE"]
            ?? UserDefaults.standard.string(forKey: Self.workspaceDefaultsKey)
    }

    public func currentWorkspace() -> String? { cachedWorkspace }

    /// Pin the workspace explicitly (e.g. from a folder picker) and persist it
    /// so the next launch resolves without cwd dependence.
    public func setWorkspace(_ path: String) {
        cachedWorkspace = path
        UserDefaults.standard.set(path, forKey: Self.workspaceDefaultsKey)
    }

    public func list() async throws -> FleetSnapshot {
        let data = try await capture(args: withWorkspace(["list", "--json"]))
        do {
            let snapshot = try JSONDecoder().decode(FleetSnapshot.self, from: data)
            cachedWorkspace = snapshot.workspace
            return snapshot
        } catch {
            throw BwocCliError.decodeFailed(String(describing: error))
        }
    }

    public func sessions() async throws -> [Session] {
        let data = try await capture(args: withWorkspace(["sessions", "--json"]))
        do {
            return try JSONDecoder().decode(SessionSnapshot.self, from: data).sessions
        } catch {
            throw BwocCliError.decodeFailed(String(describing: error))
        }
    }

    public func inbox(agent: String, limit: Int = 3) async throws -> InboxSnapshot {
        let data = try await capture(args: withWorkspace(["inbox", agent, "--json", "--limit", String(limit)]))
        do {
            return try JSONDecoder().decode(InboxSnapshot.self, from: data)
        } catch {
            throw BwocCliError.decodeFailed(String(describing: error))
        }
    }

    /// Run a non-interactive action (`start` / `stop` / `supervise`) and wait
    /// for it to finish, discarding stdout. Throws on a non-zero exit.
    public func perform(_ action: AgentAction, agent: Agent) async throws {
        precondition(!action.isInteractive, "use openInTerminal for interactive actions")
        _ = try await capture(args: action.argv(agent: agent, workspace: cachedWorkspace))
    }

    /// Launch an interactive action (`spawn` / `chat`) in Terminal.app — those
    /// flows need a real TTY and can't run inside this process.
    public func openInTerminal(_ action: AgentAction, agent: Agent) async throws {
        try await openInTerminal(argv: action.argv(agent: agent, workspace: cachedWorkspace))
    }

    /// Open `bwoc inbox <agent> --watch` in Terminal.app, workspace-qualified.
    public func openInboxWatch(agent: String) async throws {
        try await openInTerminal(argv: withWorkspace(["inbox", agent, "--watch"]))
    }

    /// Resolved `bwoc` binary path, for callers that spawn their own process
    /// (e.g. the streaming detail window).
    public func binaryPath() -> String? { binaryURL?.path }

    /// Workspace-qualified argv for a long-running stream.
    public func streamArgv(_ kind: StreamKind, agent: String) -> [String] {
        withWorkspace(kind.argv(agent: agent))
    }

    private func withWorkspace(_ args: [String]) -> [String] {
        guard let cachedWorkspace else { return args }
        return args + ["--workspace", cachedWorkspace]
    }

    /// Open Terminal.app running `bwoc <argv...>` — for any flow that needs a
    /// TTY (interactive actions, `inbox --watch`, etc.).
    private func openInTerminal(argv: [String]) async throws {
        guard let binaryURL else { throw BwocCliError.binaryNotFound }
        let command = ([binaryURL.path] + argv)
            .map(Self.shellQuote)
            .joined(separator: " ")
        let script = """
        tell application "Terminal"
            activate
            do script "\(Self.appleScriptEscape(command))"
        end tell
        """
        let osa = Process()
        osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osa.arguments = ["-e", script]
        let err = Pipe()
        osa.standardError = err
        try osa.run()
        osa.waitUntilExit()
        if osa.terminationStatus != 0 {
            let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw BwocCliError.nonZeroExit(code: osa.terminationStatus, stderr: errStr)
        }
    }

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func capture(args: [String]) async throws -> Data {
        guard let binaryURL else { throw BwocCliError.binaryNotFound }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        // Kill a wedged `bwoc` (e.g. blocked on a lock) after a timeout so a UI
        // action can't hang forever. terminate() closes the child's pipes, which
        // lets the drains below reach EOF and return.
        let timedOut = TimeoutFlag()
        let timeoutTask = Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(Self.commandTimeout * 1_000_000_000))
            if process.isRunning {
                timedOut.set()
                process.terminate()
            }
        }

        // Drain both pipes on background threads *while the child runs*. Reading
        // only after waitUntilExit() deadlocks once a command writes past the OS
        // pipe buffer (~64KB): the child blocks on write, we block on wait. The
        // `await`s also free the actor instead of blocking it for the whole run.
        async let outData = Self.readToEnd(stdout.fileHandleForReading)
        async let errData = Self.readToEnd(stderr.fileHandleForReading)
        let out = await outData
        let err = await errData

        process.waitUntilExit()   // pipes are at EOF, so this returns at once
        timeoutTask.cancel()

        if timedOut.isSet {
            throw BwocCliError.timedOut(seconds: Self.commandTimeout)
        }
        if process.terminationStatus != 0 {
            let errStr = String(data: err, encoding: .utf8) ?? ""
            throw BwocCliError.nonZeroExit(code: process.terminationStatus, stderr: errStr)
        }

        return out
    }

    /// Upper bound for a single non-interactive `bwoc` call. The commands routed
    /// through capture() (list / sessions / inbox / start / stop) all return in
    /// well under a second; interactive flows go through Terminal, not here.
    private static let commandTimeout: TimeInterval = 20

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { (cont: CheckedContinuation<Data, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }
}
