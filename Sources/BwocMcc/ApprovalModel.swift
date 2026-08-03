import Foundation
import BwocMccCore

/// Shared pending-approval state, polled by the fleet view and observed by the
/// menu-bar label (for the badge). A singleton so both surfaces see one queue.
@MainActor
final class ApprovalModel: ObservableObject {
    static let shared = ApprovalModel()

    @Published private(set) var pending: [ApprovalRequest] = []

    /// Set when the last `decide` did NOT reach disk (expired request, or a
    /// write error) so the UI can tell the operator their click had no effect,
    /// instead of the verdict silently vanishing. Cleared on a successful decide.
    @Published var lastError: String?

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

    /// Record the operator's verdict. Drops it from the local queue **only when
    /// the write reaches disk**, so a failed verdict stays visible (and retryable)
    /// rather than vanishing as if it had been delivered. Returns whether it was
    /// written.
    @discardableResult
    func decide(_ req: ApprovalRequest, allow: Bool, always: Bool, workspace: String) -> Bool {
        let ok = ApprovalInbox(workspace: workspace)
            .decide(req, allow: allow, always: always, by: ApprovalInbox.operatorIdentity)
        if ok {
            pending.removeAll { $0.id == req.id }
            lastError = nil
        } else {
            lastError = "Couldn't record the decision for \(req.tool) — it was NOT delivered "
                + "(the request may have expired, or the write failed). It stays in the queue."
        }
        return ok
    }
}
