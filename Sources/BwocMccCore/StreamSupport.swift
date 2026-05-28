import Foundation

/// A long-running `bwoc` stream the detail window can tail.
public enum StreamKind: String, Sendable, CaseIterable {
    case inbox
    case log

    public var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .log: return "Log"
        }
    }

    /// Argument vector (before workspace qualification).
    public func argv(agent: String) -> [String] {
        switch self {
        case .inbox: return ["inbox", agent, "--watch"]
        case .log: return ["log", agent, "-f"]
        }
    }
}

/// Splits an incrementally-arriving byte stream into complete lines, holding a
/// partial trailing fragment until its newline arrives. Pure + unit-tested so
/// the streaming UI can rely on stable line boundaries.
public struct LineBuffer {
    private var pending = ""

    public init() {}

    /// Append a decoded chunk; return any lines completed by it.
    public mutating func append(_ chunk: String) -> [String] {
        pending += chunk
        var lines: [String] = []
        while let newline = pending.firstIndex(of: "\n") {
            lines.append(String(pending[pending.startIndex..<newline]))
            pending = String(pending[pending.index(after: newline)...])
        }
        return lines
    }

    /// Return and clear any buffered text with no trailing newline yet.
    public mutating func flush() -> String? {
        guard !pending.isEmpty else { return nil }
        defer { pending = "" }
        return pending
    }
}
