import Foundation

/// One inbox envelope from `bwoc inbox <agent> --json`.
public struct InboxMessage: Codable, Identifiable, Hashable, Sendable {
    public var id: String { messageId }

    public let from: String
    public let to: String
    public let message: String
    public let messageId: String
    public let ts: String
}

public struct InboxSnapshot: Codable, Sendable {
    public let agent: String
    public let inbox: String
    public let messages: [InboxMessage]
    public let shown: Int
    public let total: Int
}
