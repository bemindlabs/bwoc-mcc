import Foundation

/// A backlog story as tracked in `.scrum/backlog.json`. Only the fields the
/// menu-bar strip needs are modeled; decoded with `.convertFromSnakeCase`.
public struct ScrumStory: Decodable, Sendable {
    public let id: String
    public let status: String
    public let owner: String?
    public let sprint: String?
    public let points: Int?
    public let blockedBy: [String]?

    public init(id: String, status: String, owner: String?, sprint: String?, points: Int?, blockedBy: [String]?) {
        self.id = id
        self.status = status
        self.owner = owner
        self.sprint = sprint
        self.points = points
        self.blockedBy = blockedBy
    }
}

public struct ScrumState: Sendable, Equatable {
    public let sprintId: String
    public let daysLeft: Int?
    public let pointsDone: Int
    public let pointsCommitted: Int
    public let blockedAgents: Set<String>

    public init(sprintId: String, daysLeft: Int?, pointsDone: Int, pointsCommitted: Int, blockedAgents: Set<String>) {
        self.sprintId = sprintId
        self.daysLeft = daysLeft
        self.pointsDone = pointsDone
        self.pointsCommitted = pointsCommitted
        self.blockedAgents = blockedAgents
    }
}

public enum ScrumReader {
    private struct Config: Decodable { let currentSprint: String? }
    private struct SprintFile: Decodable { let endDate: String?; let committedPoints: Int?; let status: String? }
    private struct Backlog: Decodable { let items: [ScrumStory] }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    /// Read `.scrum/` under `workspace` and derive the active-sprint snapshot.
    /// Returns nil when there is no active sprint or the tree can't be read.
    public static func read(workspace: String, now: Date = Date()) -> ScrumState? {
        let scrum = URL(fileURLWithPath: workspace).appendingPathComponent(".scrum")
        let dec = decoder()

        let configSprint = (try? Data(contentsOf: scrum.appendingPathComponent("config.json")))
            .flatMap { try? dec.decode(Config.self, from: $0) }?.currentSprint

        guard let (sprintId, sprint) = resolveActiveSprint(
            configSprint: configSprint,
            sprintsDir: scrum.appendingPathComponent("sprints"),
            dec: dec
        ) else { return nil }

        let items = (try? Data(contentsOf: scrum.appendingPathComponent("backlog.json")))
            .flatMap { try? dec.decode(Backlog.self, from: $0) }?.items ?? []

        return compute(
            sprintId: sprintId,
            endDate: sprint.endDate,
            committedPoints: sprint.committedPoints,
            items: items,
            now: now
        )
    }

    /// Resolve the sprint to display. Honor `config.current_sprint` only when it
    /// names a real, still-`active` sprint; otherwise scan the sprints directory
    /// for whichever one is `active`. The pointer is known to drift — it has been
    /// null, and can lag on a just-closed sprint — so the scan is the safety net.
    private static func resolveActiveSprint(
        configSprint: String?,
        sprintsDir: URL,
        dec: JSONDecoder
    ) -> (String, SprintFile)? {
        if let id = configSprint,
           let data = try? Data(contentsOf: sprintsDir.appendingPathComponent("\(id).json")),
           let sprint = try? dec.decode(SprintFile.self, from: data),
           sprint.status == "active" {
            return (id, sprint)
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: sprintsDir, includingPropertiesForKeys: nil
        )) ?? []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let sprint = try? dec.decode(SprintFile.self, from: data),
               sprint.status == "active" {
                return (url.deletingPathExtension().lastPathComponent, sprint)
            }
        }
        return nil
    }

    /// Pure derivation — separated from IO so it can be unit-tested.
    public static func compute(
        sprintId: String,
        endDate: String?,
        committedPoints: Int?,
        items: [ScrumStory],
        now: Date = Date()
    ) -> ScrumState {
        let pointsDone = items
            .filter { $0.sprint == sprintId && $0.status == "done" }
            .compactMap(\.points)
            .reduce(0, +)

        let statusById = Dictionary(items.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
        var blocked = Set<String>()
        for story in items where story.status != "done" {
            let hasOpenBlocker = (story.blockedBy ?? []).contains { blocker in
                if let st = statusById[blocker] { return st != "done" }
                return false
            }
            if hasOpenBlocker, let owner = story.owner {
                blocked.insert(owner)
            }
        }

        return ScrumState(
            sprintId: sprintId,
            daysLeft: endDate.flatMap { daysUntil($0, now: now) },
            pointsDone: pointsDone,
            pointsCommitted: committedPoints ?? 0,
            blockedAgents: blocked
        )
    }

    /// Whole days from `now` to a `yyyy-MM-dd` end date (negative if past).
    public static func daysUntil(_ ymd: String, now: Date = Date()) -> Int? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = "yyyy-MM-dd"
        parser.timeZone = .current
        guard let end = parser.date(from: ymd) else { return nil }
        let cal = Calendar(identifier: .gregorian)
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: end)).day
    }
}
