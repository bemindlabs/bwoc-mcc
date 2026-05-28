import Foundation

public enum BwocCliError: Error, CustomStringConvertible {
    case binaryNotFound
    case nonZeroExit(code: Int32, stderr: String)
    case decodeFailed(String)

    public var description: String {
        switch self {
        case .binaryNotFound:
            return "`bwoc` binary not found on PATH"
        case .nonZeroExit(let code, let stderr):
            return "bwoc exited \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .decodeFailed(let msg):
            return "decode failed: \(msg)"
        }
    }
}

public enum AgentAction: String, Sendable, CaseIterable {
    case spawn
    case chat
    case start
    case stop
    case supervise

    /// Interactive flows need a real TTY, so they launch in Terminal.app
    /// rather than running inside the app's process.
    public var isInteractive: Bool {
        switch self {
        case .spawn, .chat: return true
        case .start, .stop, .supervise: return false
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
        case .chat:
            return ["chat", agent.id] + Self.workspaceFlag(workspace)
        case .start, .stop, .supervise:
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

    public init() {
        self.binaryURL = Self.candidatePaths
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
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
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            throw BwocCliError.nonZeroExit(code: process.terminationStatus, stderr: errStr)
        }

        return stdout.fileHandleForReading.readDataToEndOfFile()
    }
}
