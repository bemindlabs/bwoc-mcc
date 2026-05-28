import Foundation

public struct Agent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let backend: String
    public let status: String
    public let running: Bool
    public let inboxCount: Int
    public let uptimeSeconds: Int
    public let incarnated: String
    public let path: String

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

public struct FleetSnapshot: Codable, Sendable {
    public let agents: [Agent]
    public let workspace: String
}
