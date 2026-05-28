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

if failures.isEmpty {
    print("\nall checks passed")
    exit(0)
} else {
    print("\n\(failures.count) check(s) failed")
    exit(1)
}
