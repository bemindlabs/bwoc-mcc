import Foundation

public struct Agent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let backend: String
    public let status: String
    public let running: Bool
    public let inboxCount: Int
    public let path: String
    // Not load-bearing for the UI — optional so a future CLI that drops them
    // degrades gracefully instead of failing the whole decode.
    public let uptimeSeconds: Int?
    public let incarnated: String?

    enum CodingKeys: String, CodingKey {
        case id
        case backend
        case status
        case running
        case inboxCount = "inbox_count"
        case uptimeSeconds = "uptime_seconds"
        case incarnated
        case path
    }
}

extension Agent {
    /// Backends whose sessions a native `bwoc-chat` window can render via the
    /// harness `chat_proto` stream: the OpenAI-compatible HTTP path plus the
    /// native Anthropic provider. Other vendor CLIs (codex / kimi / agy) emit no
    /// such stream.
    public static let chatWindowBackends: Set<String> = [
        "ollama", "openai-compatible", "claude", "anthropic",
    ]

    /// Whether `bwoc-chat` can open a native window for this agent. Other
    /// vendor-CLI backends (codex / kimi / agy) fall back to `bwoc chat` in a
    /// Terminal, which is all they support.
    public var supportsChatWindow: Bool {
        Self.chatWindowBackends.contains(backend)
    }

    /// A Claude-family agent. When every agent in a window is Claude-backed,
    /// `bwoc-chat` is launched with `--claude-code` so it drives the `claude`
    /// CLI via the logged-in subscription (no `ANTHROPIC_API_KEY`) instead of
    /// the harness Anthropic provider.
    public var isClaudeBacked: Bool {
        backend == "claude" || backend == "anthropic"
    }
}

public struct FleetSnapshot: Codable, Sendable {
    public let agents: [Agent]
    public let workspace: String
}
