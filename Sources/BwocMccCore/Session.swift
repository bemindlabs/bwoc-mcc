import Foundation

/// A live backend session as reported by `bwoc sessions --json`.
///
/// Note: unlike `bwoc list`, the sessions endpoint already emits camelCase
/// keys, so no CodingKeys remapping is needed.
public struct Session: Codable, Identifiable, Hashable, Sendable {
    public var id: Int { pid }

    public let pid: Int
    public let backend: String
    public let source: String       // "marker" (bound, healthy) | "scan" (orphan)
    public let state: String        // "running" | "idle"
    public let agentId: String?
    public let lastActivity: String?
    public let startedAt: String?
    public let tmux: String?

    /// A bare backend process with no agent binding — likely orphaned.
    public var isOrphan: Bool { source == "scan" }
    public var isRunning: Bool { state == "running" }
}

public struct SessionSnapshot: Codable, Sendable {
    public let sessions: [Session]
}
