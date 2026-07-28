import Foundation

/// A pending request for operator approval of a gated tool call, emitted by the
/// harness under `<workspace>/.bwoc/approvals/pending/<id>.json` when an
/// `ask`-mode tool has no TTY. Mirrors the Rust `ApprovalRequest` (snake_case on
/// the wire).
public struct ApprovalRequest: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let agent: String
    public let tool: String
    public let argsPreview: String
    public let trust: String
    public let tsMs: Double
    public let timeoutS: Int

    enum CodingKeys: String, CodingKey {
        case id, agent, tool, trust
        case argsPreview = "args_preview"
        case tsMs = "ts_ms"
        case timeoutS = "timeout_s"
    }

    /// Wall-clock instant the request was raised.
    public var date: Date { Date(timeIntervalSince1970: tsMs / 1000) }
}

/// The operator's verdict, written back to `decided/<id>.json`. Field names
/// match the Rust `ApprovalDecision` verbatim.
public struct ApprovalDecision: Codable, Sendable {
    public let allow: Bool
    public let always: Bool
    public let by: String

    public init(allow: Bool, always: Bool, by: String) {
        self.allow = allow
        self.always = always
        self.by = by
    }
}

/// Reads pending approval requests from `<workspace>/.bwoc/approvals/pending/`
/// and writes verdicts to `decided/`. The harness watches `decided/` and cleans
/// up both files once it consumes the verdict, so this type only ever reads
/// pending + writes decided.
public struct ApprovalInbox: Sendable {
    public let root: URL

    public init(workspace: String) {
        root = URL(fileURLWithPath: workspace)
            .appendingPathComponent(".bwoc")
            .appendingPathComponent("approvals")
    }

    private var pendingDir: URL { root.appendingPathComponent("pending") }
    private var decidedDir: URL { root.appendingPathComponent("decided") }

    /// Current pending requests, oldest first. Missing dir / unreadable or
    /// half-written files are skipped (the harness writes atomically, so a
    /// decode failure is a torn read we'll pick up next poll).
    public func pending() -> [ApprovalRequest] {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: pendingDir,
                includingPropertiesForKeys: nil
            )
        else { return [] }
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ApprovalRequest.self, from: data)
            }
            .sorted { $0.tsMs < $1.tsMs }
    }

    /// Write the operator's verdict for `req` atomically. `by` records who
    /// decided (provenance only). No-op on encode/IO failure — the harness falls
    /// back to fail-safe on timeout, so a dropped verdict never opens a hole.
    public func decide(_ req: ApprovalRequest, allow: Bool, always: Bool = false, by: String) {
        try? FileManager.default.createDirectory(
            at: decidedDir, withIntermediateDirectories: true
        )
        let decision = ApprovalDecision(allow: allow, always: always, by: by)
        guard let data = try? JSONEncoder().encode(decision) else { return }
        try? data.write(to: decidedDir.appendingPathComponent("\(req.id).json"), options: .atomic)
    }

    /// A stable "who" string for the `by` field, e.g. `alice@studio.local`.
    public static var operatorIdentity: String {
        "\(NSUserName())@\(ProcessInfo.processInfo.hostName)"
    }
}
