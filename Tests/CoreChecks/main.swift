import Foundation
import BwocMccCore

var failures: [String] = []

func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        print("ok    \(name)")
    } else {
        let suffix = detail()
        print("FAIL  \(name)\(suffix.isEmpty ? "" : " — \(suffix)")")
        failures.append(name)
    }
}

// 1. FleetSnapshot decodes the shape `bwoc list --json` actually emits.
let sample = #"""
{
  "agents": [
    {
      "backend": "claude",
      "id": "agent-jisoo",
      "inbox_count": 3,
      "incarnated": "2026-05-26T04:13:08Z",
      "path": "agents/agent-jisoo",
      "running": true,
      "status": "active",
      "uptime_seconds": 1234
    }
  ],
  "workspace": "/Users/x/ws"
}
"""#

do {
    let snap = try JSONDecoder().decode(FleetSnapshot.self, from: Data(sample.utf8))
    check("FleetSnapshot decodes 1 agent", snap.agents.count == 1)
    let a = snap.agents[0]
    check("agent.id maps", a.id == "agent-jisoo")
    check("agent.inboxCount maps from snake_case", a.inboxCount == 3)
    check("agent.uptimeSeconds maps from snake_case", a.uptimeSeconds == 1234)
    check("agent.running maps", a.running == true)
    check("workspace maps", snap.workspace == "/Users/x/ws")
} catch {
    check("FleetSnapshot decodes 1 agent", false, "\(error)")
}

// 2. AgentAction interactivity + argv mapping (MCC-1).
check("spawn is interactive", AgentAction.spawn.isInteractive)
check("chat is interactive", AgentAction.chat.isInteractive)
check("start is non-interactive", !AgentAction.start.isInteractive)
check("stop is non-interactive", !AgentAction.stop.isInteractive)
check("supervise is non-interactive", !AgentAction.supervise.isInteractive)
// argv is workspace-aware: name actions take `--workspace`, spawn takes `--path`.
let argvAgent = try JSONDecoder().decode(FleetSnapshot.self, from: Data(sample.utf8)).agents[0]
check("stop argv carries --workspace",
      AgentAction.stop.argv(agent: argvAgent, workspace: "/ws") == ["stop", "agent-jisoo", "--workspace", "/ws"])
check("chat argv carries --workspace",
      AgentAction.chat.argv(agent: argvAgent, workspace: "/ws") == ["chat", "agent-jisoo", "--workspace", "/ws"])
check("spawn argv targets agent dir via --path",
      AgentAction.spawn.argv(agent: argvAgent, workspace: "/ws") == ["spawn", "--path", "/ws/agents/agent-jisoo"])
check("nil workspace omits --workspace flag",
      AgentAction.stop.argv(agent: argvAgent, workspace: nil) == ["stop", "agent-jisoo"])
check("spawn with nil workspace falls back to relative path",
      AgentAction.spawn.argv(agent: argvAgent, workspace: nil) == ["spawn", "--path", "agents/agent-jisoo"])

// 3. Shell/AppleScript escaping guards (MCC-1) — quoting must neutralize
//    embedded quotes so a crafted agent id cannot break out of the command.
check("shellQuote wraps in single quotes", BwocCli.shellQuote("agent-rose") == "'agent-rose'")
check("shellQuote neutralizes embedded single quote",
      BwocCli.shellQuote("a'b") == "'a'\\''b'")
check("appleScriptEscape escapes double quote",
      BwocCli.appleScriptEscape("say \"hi\"") == "say \\\"hi\\\"")
check("appleScriptEscape escapes backslash",
      BwocCli.appleScriptEscape("a\\b") == "a\\\\b")

// 4. SessionSnapshot decodes the camelCase shape `bwoc sessions --json` emits (MCC-2).
let sessionSample = #"""
{
  "sessions": [
    { "agentId": "agent-lisa", "backend": "claude", "lastActivity": "2026-05-28T09:00:00Z", "pid": 100, "source": "marker", "startedAt": "2026-05-28T08:00:00Z", "state": "running", "tmux": null },
    { "agentId": null, "backend": "claude", "lastActivity": null, "pid": 200, "source": "scan", "startedAt": null, "state": "idle", "tmux": null }
  ]
}
"""#

do {
    let snap = try JSONDecoder().decode(SessionSnapshot.self, from: Data(sessionSample.utf8))
    check("SessionSnapshot decodes 2 sessions", snap.sessions.count == 2)
    let marker = snap.sessions[0]
    let scan = snap.sessions[1]
    check("session.pid is Identifiable id", marker.id == 100)
    check("marker session is not orphan", !marker.isOrphan)
    check("marker session running", marker.isRunning)
    check("scan session is orphan", scan.isOrphan)
    check("scan session agentId is nil", scan.agentId == nil)
    check("scan session idle is not running", !scan.isRunning)
} catch {
    check("SessionSnapshot decodes 2 sessions", false, "\(error)")
}

// 5. InboxSnapshot decodes `bwoc inbox <agent> --json` (MCC-3).
let inboxSample = #"""
{
  "agent": "agent-jisoo",
  "inbox": "/ws/agents/agent-jisoo/.bwoc/inbox.jsonl",
  "messages": [
    { "from": "agent-lisa", "message": "BWOC-53 done", "messageId": "msg-1", "to": "agent-jisoo", "ts": "2026-05-28T09:36:09Z" }
  ],
  "shown": 1,
  "total": 1
}
"""#

do {
    let snap = try JSONDecoder().decode(InboxSnapshot.self, from: Data(inboxSample.utf8))
    check("InboxSnapshot decodes agent", snap.agent == "agent-jisoo")
    check("InboxSnapshot shown/total", snap.shown == 1 && snap.total == 1)
    check("InboxSnapshot decodes 1 message", snap.messages.count == 1)
    let m = snap.messages[0]
    check("message.id maps to messageId", m.id == "msg-1")
    check("message.from maps", m.from == "agent-lisa")
    check("message.ts maps", m.ts == "2026-05-28T09:36:09Z")
} catch {
    check("InboxSnapshot decodes 1 message", false, "\(error)")
}

// 6. ScrumReader.compute derives points + blocked agents (MCC-4).
let scrumItems = [
    ScrumStory(id: "MCC-1", status: "done", owner: "agent-lisa", sprint: "sprint-8", points: 5, blockedBy: []),
    ScrumStory(id: "MCC-2", status: "done", owner: "agent-lisa", sprint: "sprint-8", points: 3, blockedBy: []),
    ScrumStory(id: "MCC-3", status: "backlog", owner: "agent-lisa", sprint: "sprint-8", points: 3, blockedBy: []),
    // MCC-5 is open and blocked by MCC-3 (still open) -> owner is blocked.
    ScrumStory(id: "MCC-5", status: "backlog", owner: "agent-rose", sprint: "sprint-8", points: 8, blockedBy: ["MCC-3"]),
    // A story blocked only by a DONE story is NOT blocked.
    ScrumStory(id: "MCC-9", status: "backlog", owner: "agent-jennie", sprint: "sprint-8", points: 2, blockedBy: ["MCC-1"]),
]
let scrumState = ScrumReader.compute(
    sprintId: "sprint-8",
    endDate: "2026-06-04",
    committedPoints: 22,
    items: scrumItems,
    now: ISO8601DateFormatter().date(from: "2026-05-30T00:00:00Z")!
)
check("pointsDone sums only done-in-sprint", scrumState.pointsDone == 8)
check("pointsCommitted from sprint file", scrumState.pointsCommitted == 22)
check("agent blocked by open blocker", scrumState.blockedAgents.contains("agent-rose"))
check("agent NOT blocked when blocker is done", !scrumState.blockedAgents.contains("agent-jennie"))
check("done story owner not flagged blocked", !scrumState.blockedAgents.contains("agent-lisa"))

// 7. daysUntil date math (MCC-4).
let fixedNow = ISO8601DateFormatter().date(from: "2026-05-30T12:00:00Z")!
check("daysUntil future date", ScrumReader.daysUntil("2026-06-04", now: fixedNow) == 5)
check("daysUntil malformed returns nil", ScrumReader.daysUntil("not-a-date") == nil)

// 8. LineBuffer splits an incremental stream on newlines (MCC-6).
var lb = LineBuffer()
check("complete lines split immediately", lb.append("a\nb\n") == ["a", "b"])
check("partial line withheld until newline", lb.append("par") == [])
check("partial completes on next chunk", lb.append("tial\nnext\n") == ["partial", "next"])
check("flush returns trailing fragment", { lb.append("tail"); return lb.flush() }() == "tail")
check("flush is empty after drain", lb.flush() == nil)
var lb2 = LineBuffer()
check("blank lines preserved", lb2.append("\n\nx\n") == ["", "", "x"])

// 9. StreamKind argv (MCC-6).
check("inbox stream argv", StreamKind.inbox.argv(agent: "agent-lisa") == ["inbox", "agent-lisa", "--watch"])
check("log stream argv", StreamKind.log.argv(agent: "agent-lisa") == ["log", "agent-lisa", "-f"])

// 10. BwocCli seeds workspace from BWOC_WORKSPACE before any list() (MCC-7).
setenv("BWOC_WORKSPACE", "/tmp/seeded-ws", 1)
let seeded = await BwocCli().currentWorkspace()
check("BWOC_WORKSPACE seeds cachedWorkspace at init", seeded == "/tmp/seeded-ws")
unsetenv("BWOC_WORKSPACE")

if failures.isEmpty {
    print("\nall checks passed")
    exit(0)
} else {
    print("\n\(failures.count) check(s) failed")
    exit(1)
}
