import Foundation

public enum BwocCliError: Error, CustomStringConvertible {
    case binaryNotFound
    case chatBinaryNotFound
    case nonZeroExit(code: Int32, stderr: String)
    case decodeFailed(String)
    case timedOut(seconds: TimeInterval)

    public var description: String {
        switch self {
        case .binaryNotFound:
            return "`bwoc` binary not found on PATH"
        case .chatBinaryNotFound:
            return "`bwoc-chat` not found — install it (cargo install --path projects/bwoc-chat) or set its path in Settings"
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

/// Terminal emulator used for interactive flows. Terminal and iTerm speak
/// different AppleScript dialects, so the choice drives which script is sent.
public enum TerminalApp: String, CaseIterable, Sendable {
    case terminal = "Terminal"
    case iterm = "iTerm"

    public static let defaultsKey = "bwoc.terminalApp"
}

public actor BwocCli {
    public static let shared = BwocCli()

    private static let candidatePaths: [String] = [
        "/opt/homebrew/bin/bwoc",
        "/usr/local/bin/bwoc",
        NSString(string: "~/.local/bin/bwoc").expandingTildeInPath,
        NSString(string: "~/.cargo/bin/bwoc").expandingTildeInPath
    ]

    /// Well-known install dirs for the sibling `bwoc-chat` GUI binary. Probed
    /// after a user override and a sibling of the resolved `bwoc` (they're
    /// normally installed together, e.g. both under `~/.cargo/bin`).
    private static let chatCandidatePaths: [String] = [
        "/opt/homebrew/bin/bwoc-chat",
        "/usr/local/bin/bwoc-chat",
        NSString(string: "~/.local/bin/bwoc-chat").expandingTildeInPath,
        NSString(string: "~/.cargo/bin/bwoc-chat").expandingTildeInPath
    ]

    private let binaryURL: URL?
    private let chatBinaryURL: URL?

    /// Learned from the first successful `list()` and then passed as
    /// `--workspace` to every subsequent command, so actions resolve the right
    /// workspace even when the host process (or a spawned Terminal) has a cwd
    /// outside the workspace tree.
    private var cachedWorkspace: String? = nil

    static let workspaceDefaultsKey = "bwoc.workspacePath"
    public static let binaryDefaultsKey = "bwoc.binaryPath"
    public static let chatBinaryDefaultsKey = "bwoc.chatBinaryPath"

    public init() {
        // A user-set override (Settings) wins over the built-in candidates.
        let override = UserDefaults.standard.string(forKey: Self.binaryDefaultsKey)
            .flatMap { $0.isEmpty ? nil : $0 }
        let candidates = (override.map { [$0] } ?? []) + Self.candidatePaths
        let resolvedBwoc = candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        self.binaryURL = resolvedBwoc

        // Resolve the sibling `bwoc-chat` GUI: an override, then next to the
        // resolved `bwoc`, then the well-known bin dirs.
        let chatOverride = UserDefaults.standard.string(forKey: Self.chatBinaryDefaultsKey)
            .flatMap { $0.isEmpty ? nil : $0 }
        let sibling = resolvedBwoc?.deletingLastPathComponent()
            .appendingPathComponent("bwoc-chat").path
        let chatCandidates = (chatOverride.map { [$0] } ?? [])
            + (sibling.map { [$0] } ?? [])
            + Self.chatCandidatePaths
        self.chatBinaryURL = chatCandidates
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

    /// Resolved `bwoc-chat` GUI binary path (nil if not installed) — surfaced in
    /// Settings and used to decide whether the native chat window is available.
    public func chatBinaryPath() -> String? { chatBinaryURL?.path }

    /// Argv for `bwoc-chat`: the agent id(s), an optional `--claude-code` (drive
    /// the `claude` CLI via subscription), then an explicit `--workspace` so the
    /// window resolves the right registry even when launched with a cwd outside
    /// the workspace tree (e.g. a double-clicked .app). Naming several agents
    /// opens one shared team-chat window. Pure + testable.
    public static func chatArgv(
        agents: [String],
        workspace: String?,
        claudeCode: Bool = false
    ) -> [String] {
        var argv = agents
        if claudeCode { argv.append("--claude-code") }
        if let workspace { argv += ["--workspace", workspace] }
        return argv
    }

    /// Open the native `bwoc-chat` window for one or more agents. Fire-and-forget:
    /// `bwoc-chat` is its own GUI process owning its window + harness children, so
    /// it's launched detached (no pipes, no wait) and outlives this menu-bar app —
    /// the same lifecycle as a `bwoc chat` Terminal window. Throws if `bwoc-chat`
    /// is unresolved or the spawn fails; the caller can then fall back to Terminal.
    public func openChatWindow(agents: [Agent]) throws {
        guard let chatBinaryURL else { throw BwocCliError.chatBinaryNotFound }
        // All-Claude selection → drive the `claude` CLI (subscription auth, no
        // API key). A mixed or non-Claude window uses the harness path, since
        // `--claude-code` is window-wide in bwoc-chat.
        let claudeCode = !agents.isEmpty && agents.allSatisfy(\.isClaudeBacked)
        let proc = Process()
        proc.executableURL = chatBinaryURL
        proc.arguments = Self.chatArgv(
            agents: agents.map(\.id),
            workspace: cachedWorkspace,
            claudeCode: claudeCode
        )
        // Launch from the workspace so bwoc-chat's `@`-file completion lists
        // workspace files rather than the host app's cwd ("/"). Harmless if unset.
        if let cachedWorkspace {
            proc.currentDirectoryURL = URL(fileURLWithPath: cachedWorkspace)
        }
        try proc.run()
    }

    /// Workspace-qualified argv for a long-running stream.
    public func streamArgv(_ kind: StreamKind, agent: String) -> [String] {
        withWorkspace(kind.argv(agent: agent))
    }

    private func withWorkspace(_ args: [String]) -> [String] {
        guard let cachedWorkspace else { return args }
        return args + ["--workspace", cachedWorkspace]
    }

    /// Open the chosen terminal running `bwoc <argv...>` — for any flow that
    /// needs a TTY (interactive actions, `inbox --watch`, etc.).
    private func openInTerminal(argv: [String]) async throws {
        guard let binaryURL else { throw BwocCliError.binaryNotFound }
        let command = ([binaryURL.path] + argv)
            .map(Self.shellQuote)
            .joined(separator: " ")
        let app = TerminalApp(rawValue: UserDefaults.standard.string(forKey: TerminalApp.defaultsKey) ?? "") ?? .terminal
        let script = Self.terminalScript(app, command: command)

        let osa = Process()
        osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osa.arguments = ["-e", script]
        let err = Pipe()
        osa.standardError = err
        try osa.run()
        // Drain stderr while osascript runs — same pipe-deadlock guard as capture().
        async let errData = Self.readToEnd(err.fileHandleForReading)
        let errOut = await errData
        osa.waitUntilExit()
        if osa.terminationStatus != 0 {
            let errStr = String(data: errOut, encoding: .utf8) ?? ""
            throw BwocCliError.nonZeroExit(code: osa.terminationStatus, stderr: errStr)
        }
    }

    /// AppleScript that opens `command` in `app`. Terminal and iTerm use
    /// different verbs to spawn a window+command, so each has its own template.
    public static func terminalScript(_ app: TerminalApp, command: String) -> String {
        let escaped = appleScriptEscape(command)
        switch app {
        case .terminal:
            return """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        case .iterm:
            return """
            tell application "iTerm"
                activate
                create window with default profile command "\(escaped)"
            end tell
            """
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
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()   // SIGTERM — graceful
            // A child that ignores SIGTERM (blocked on a lock, signal-masked)
            // keeps its stdout pipe open, so the drains never reach EOF and
            // capture() would hang forever despite the "timeout". Escalate to
            // SIGKILL, which can't be caught → the pipe closes → the reads
            // unblock and capture() returns with the timeout error.
            try? await Task.sleep(nanoseconds: UInt64(Self.terminateGrace * 1_000_000_000))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
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

    /// Grace between SIGTERM and the SIGKILL escalation in the timeout path.
    private static let terminateGrace: TimeInterval = 2

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { (cont: CheckedContinuation<Data, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }
}
