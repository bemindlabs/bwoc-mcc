import Foundation
import BwocMccCore

/// Shared pending-approval state, polled by the fleet view and observed by the
/// menu-bar label (for the badge). A singleton so both surfaces see one queue.
@MainActor
final class ApprovalModel: ObservableObject {
    static let shared = ApprovalModel()

    @Published private(set) var pending: [ApprovalRequest] = []

    private init() {}

    /// Re-read the pending queue for `workspace`. Directory scan + JSON decode
    /// run off the main actor (blocking file IO).
    func refresh(workspace: String?) async {
        guard let ws = workspace else {
            pending = []
            return
        }
        let inbox = ApprovalInbox(workspace: ws)
        pending = await Task.detached { inbox.pending() }.value
    }

    /// Record the operator's verdict and drop it from the local queue at once —
    /// the harness deletes the files on consume, so optimistic removal keeps the
    /// UI responsive without waiting for the next poll.
    func decide(_ req: ApprovalRequest, allow: Bool, always: Bool, workspace: String) {
        ApprovalInbox(workspace: workspace)
            .decide(req, allow: allow, always: always, by: ApprovalInbox.operatorIdentity)
        pending.removeAll { $0.id == req.id }
    }
}
