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

    /// `bwoc <verb> <agent>` argument vector for this action.
    public func argv(agent: String) -> [String] {
        [rawValue, agent]
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

    public init() {
        self.binaryURL = Self.candidatePaths
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public func list() async throws -> FleetSnapshot {
        let data = try await capture(args: ["list", "--json"])
        do {
            return try JSONDecoder().decode(FleetSnapshot.self, from: data)
        } catch {
            throw BwocCliError.decodeFailed(String(describing: error))
        }
    }

    public func sessions() async throws -> [Session] {
        let data = try await capture(args: ["sessions", "--json"])
        do {
            return try JSONDecoder().decode(SessionSnapshot.self, from: data).sessions
        } catch {
            throw BwocCliError.decodeFailed(String(describing: error))
        }
    }

    /// Run a non-interactive action (`start` / `stop` / `supervise`) and wait
    /// for it to finish, discarding stdout. Throws on a non-zero exit.
    public func perform(_ action: AgentAction, agent: String) async throws {
        precondition(!action.isInteractive, "use openInTerminal for interactive actions")
        _ = try await capture(args: action.argv(agent: agent))
    }

    /// Launch an interactive action (`spawn` / `chat`) in Terminal.app — those
    /// flows need a real TTY and can't run inside this process.
    public func openInTerminal(_ action: AgentAction, agent: String) async throws {
        guard let binaryURL else { throw BwocCliError.binaryNotFound }
        let command = ([binaryURL.path] + action.argv(agent: agent))
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
