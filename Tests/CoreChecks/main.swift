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
check("stop argv maps to [stop, agent]", AgentAction.stop.argv(agent: "agent-rose") == ["stop", "agent-rose"])
check("start argv maps to [start, agent]", AgentAction.start.argv(agent: "agent-lisa") == ["start", "agent-lisa"])

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

if failures.isEmpty {
    print("\nall checks passed")
    exit(0)
} else {
    print("\n\(failures.count) check(s) failed")
    exit(1)
}
