import SwiftUI
import BwocMccCore

/// Owns the live desktop mascots and exposes spawn / dismiss to the UI.
///
/// Keyed by id: a generic free-roaming mascot uses `defaultID`; a mascot sent
/// out for a specific agent is keyed by the agent id and captioned with it, so
/// spawning the same agent twice just toggles its one mascot.
@MainActor
final class MascotManager: ObservableObject {
    static let shared = MascotManager()

    static let defaultID = "·desktop·"

    /// Ids of mascots currently on screen — drives button state in the menu.
    @Published private(set) var active: Set<String> = []

    /// Latest fleet snapshot, pushed by the menu's refresh so agent mascots can
    /// read live `running` state without each polling `bwoc list`.
    private var fleet: FleetSnapshot?

    private var agents: [String: MascotAgent] = [:]

    private init() {}

    /// Whether the plain free-roaming desktop mascot is out.
    var desktopMascotShown: Bool { active.contains(Self.defaultID) }

    func toggleDesktopMascot() {
        toggle(id: Self.defaultID, agentID: nil, caption: nil)
    }

    /// Send a mascot to the desktop for a specific agent (captioned with its id).
    func toggleAgentMascot(_ agentID: String) {
        toggle(id: agentID, agentID: agentID, caption: agentID)
    }

    func isShown(_ id: String) -> Bool { active.contains(id) }

    /// Feed the latest fleet state to live agent mascots (called from the menu).
    func updateFleet(_ snapshot: FleetSnapshot) {
        fleet = snapshot
    }

    private func toggle(id: String, agentID: String?, caption: String?) {
        if let existing = agents[id] {
            existing.dismiss()              // calls back into remove() via onClosed
            return
        }
        guard !MascotSprite.frames.isEmpty else { return }   // no asset → no-op
        let agent = MascotAgent(id: id, agentID: agentID, caption: caption)
        agent.onClosed = { [weak self] cid in self?.remove(cid) }
        // Read the mascot's *current* binding (it can be reassigned via its
        // right-click menu), so running-state and the assign list stay live.
        agent.runningProvider = { [weak self, weak agent] in
            guard let aid = agent?.agentID else { return false }
            return self?.fleet?.agents.first { $0.id == aid }?.running ?? false
        }
        agent.fleetProvider = { [weak self] in self?.fleet?.agents ?? [] }
        agents[id] = agent
        active.insert(id)
        agent.spawn()
    }

    func dismissAll() {
        for agent in agents.values { agent.dismiss() }
    }

    private func remove(_ id: String) {
        agents[id] = nil
        active.remove(id)
    }
}
