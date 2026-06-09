import AppKit
import BwocMccCore

/// One floating desktop mascot — a tiny on-screen pet for an agent (or a generic
/// desktop companion). It:
///   • wanders on its own, facing the way it walks (8-view sprite),
///   • reacts to the mouse — perks up and walks toward a nearby cursor, beams
///     when hovered or petted (click), can be dragged, double-clicked to dismiss,
///   • shows moods via an emote glyph (❤️ petted · ❗ new message · ❔ curious ·
///     ⚙️ working · 💤 sleepy),
///   • and, when bound to an agent, speaks the agent's latest inbox message in a
///     bubble and perks up to ❗ when a new one lands.
///
/// Lifecycle is owned by `MascotManager`; `onClosed` lets it drop its reference.
final class MascotAgent: NSObject {
    let id: String
    /// The bound agent id (nil for the generic free-roaming desktop mascot).
    /// Reassignable at runtime via the right-click "Assign agent" menu.
    private(set) var agentID: String?
    var onClosed: ((String) -> Void)?
    /// Lets the mascot read live agent state (running?) from the manager's fleet
    /// snapshot without polling `bwoc list` itself.
    var runningProvider: (() -> Bool)?
    /// Supplies the current fleet for the right-click "Assign agent" menu.
    var fleetProvider: (() -> [Agent])?

    private let panel: NSPanel
    private let view: MascotView
    private let bubblePanel: NSPanel
    private let bubbleView: MascotBubbleView
    private var timer: Timer?
    private var pollTimer: Timer?

    // Position / wander.
    private var center: CGPoint = .zero
    private var wanderTarget: CGPoint = .zero
    private var pauseUntil: CGFloat = 0
    private var clock: CGFloat = 0
    private var bobPhase: CGFloat = 0
    private var dragging = false

    // Interaction / mood.
    private var hovering = false
    private var petUntil: CGFloat = 0
    private var alertUntil: CGFloat = 0
    private var lastInteract: CGFloat = 0

    // Bubble / message.
    private var message: String? = nil
    private var messageUntil: CGFloat = 0
    private var lastMessageId: String? = nil
    private var seenFirstPoll = false

    private let speed: CGFloat = 58
    private let arrive: CGFloat = 8
    private let tick: CGFloat = 1.0 / 60.0
    private let nearRadius: CGFloat = 150     // cursor proximity that makes it curious
    private let followGap: CGFloat = 40       // how close it walks to the cursor
    private let sleepDelay: CGFloat = 22      // idle seconds before it dozes off

    init(id: String, agentID: String?, caption: String?) {
        self.id = id
        self.agentID = agentID
        let h: CGFloat = caption == nil ? 116 : 128
        let w = max(124, ceil(96 * MascotSprite.aspect))
        let size = NSSize(width: w, height: h)

        view = MascotView(frame: NSRect(origin: .zero, size: size))
        view.caption = caption

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        bubbleView = MascotBubbleView(frame: .zero)
        bubblePanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        super.init()

        for p in [panel, bubblePanel] {
            p.isFloatingPanel = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }
        panel.contentView = view
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false   // drags are routed via the view
        bubblePanel.contentView = bubbleView
        bubblePanel.ignoresMouseEvents = true        // never steals desktop clicks

        view.onDismiss = { [weak self] in self?.dismiss() }
        view.onDragBegan = { [weak self] in self?.dragging = true }
        view.onDragEnded = { [weak self] in self?.endDrag() }
        view.onHover = { [weak self] over in self?.setHover(over) }
        view.onPet = { [weak self] in self?.pet() }
        view.onRightClick = { [weak self] event in self?.showAssignMenu(event) }
    }

    /// Place the mascot at the bottom-centre of the active screen and start it.
    func spawn() {
        let area = visibleArea()
        center = CGPoint(x: area.midX, y: area.minY + panel.frame.height / 2 + 20)
        applyCenter()
        panel.orderFrontRegardless()
        pickWanderTarget()

        let t = Timer(timeInterval: TimeInterval(tick), repeats: true) { [weak self] _ in
            self?.step()
        }
        RunLoop.main.add(t, forMode: .common)   // keep moving during menu tracking
        timer = t
        startPolling()
    }

    /// (Re)start inbox polling for the bound agent; a no-op when free-roaming.
    private func startPolling() {
        pollTimer?.invalidate(); pollTimer = nil
        guard agentID != nil else { return }
        pollMessages()
        let p = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            self?.pollMessages()
        }
        RunLoop.main.add(p, forMode: .common)
        pollTimer = p
    }

    // MARK: - Assignment

    /// Bind (or unbind) this mascot to an agent at runtime. Resets the bubble and
    /// restarts inbox polling for the new agent.
    func assign(agentID newID: String?) {
        agentID = newID
        view.caption = newID
        lastMessageId = nil
        seenFirstPoll = false
        message = nil
        messageUntil = 0
        alertUntil = 0
        bubbleView.text = ""
        bubblePanel.orderOut(nil)
        startPolling()
    }

    /// Right-click → choose which agent this mascot represents.
    private func showAssignMenu(_ event: NSEvent) {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Assign agent", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for agent in fleetProvider?() ?? [] {
            let item = NSMenuItem(title: agent.id,
                                  action: #selector(pickAgent(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = agent.id
            item.state = (agent.id == agentID) ? .on : .off
            // Green dot for a running agent, hollow for stopped.
            let dot = NSImage(systemSymbolName: agent.running ? "circle.fill" : "circle",
                              accessibilityDescription: nil)
            item.image = dot?.withSymbolConfiguration(
                .init(paletteColors: [agent.running ? .systemGreen : .secondaryLabelColor]))
            menu.addItem(item)
        }

        menu.addItem(.separator())
        if agentID != nil {
            let detach = NSMenuItem(title: "Detach (free roam)",
                                    action: #selector(detachAgent), keyEquivalent: "")
            detach.target = self
            menu.addItem(detach)
        }
        let dismiss = NSMenuItem(title: "Dismiss mascot",
                                 action: #selector(dismissFromMenu), keyEquivalent: "")
        dismiss.target = self
        menu.addItem(dismiss)

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func pickAgent(_ sender: NSMenuItem) {
        assign(agentID: sender.representedObject as? String)
    }

    @objc private func detachAgent() { assign(agentID: nil) }
    @objc private func dismissFromMenu() { dismiss() }

    func dismiss() {
        timer?.invalidate(); timer = nil
        pollTimer?.invalidate(); pollTimer = nil
        bubblePanel.orderOut(nil)
        panel.orderOut(nil)
        onClosed?(id)
    }

    // MARK: - Mouse

    private func setHover(_ over: Bool) {
        hovering = over
        if over {
            lastInteract = clock
            // Hovering an agent mascot asks "what are you up to?" — surface its
            // latest line (or status) for a few seconds.
            refreshBubbleForHover()
        }
    }

    private func pet() {
        petUntil = clock + 1.2
        lastInteract = clock
    }

    // MARK: - Behaviour loop

    private func step() {
        clock += tick
        bobPhase += tick
        defer { syncBubble() }

        guard !dragging else { return }

        let cursor = NSEvent.mouseLocation
        let dCursor = hypot(cursor.x - center.x, cursor.y - center.y)
        let running = runningProvider?() ?? false

        // Mood priority: pet > hover > new-message alert > curious(cursor) >
        // working > sleepy > wander.
        if clock < petUntil {
            beHappy(intense: true)
        } else if hovering {
            beHappy(intense: false)
        } else if clock < alertUntil {
            beAlert()
        } else if dCursor < nearRadius {
            beCurious(toward: cursor, distance: dCursor)
        } else if running {
            beWorking()
        } else if clock - lastInteract > sleepDelay && clock > messageUntil {
            beSleepy()
        } else {
            beWander()
        }
    }

    private func beHappy(intense: Bool) {
        view.frameIndex = 0                       // face the viewer
        view.emote = "❤️"
        view.emotePop = intense ? bouncing(speedHz: 9) : bouncing(speedHz: 4) * 0.5
        view.bob = abs(sin(bobPhase * (intense ? 10 : 5))) * (intense ? 5 : 3)
    }

    private func beAlert() {
        view.frameIndex = 0
        view.emote = "❗"
        view.emotePop = bouncing(speedHz: 8)
        view.bob = abs(sin(bobPhase * 11)) * 4
    }

    private func beCurious(toward p: CGPoint, distance: CGFloat) {
        lastInteract = clock
        view.emote = "❔"
        view.emotePop = 0
        if distance > followGap {
            walk(toward: p)                       // amble over to the cursor
        } else {
            view.frameIndex = MascotSprite.frameIndex(headingDegrees: heading(to: p))
            view.bob = sin(bobPhase * 2.4) * 1.5  // arrived — look up, idle
        }
    }

    private func beWorking() {
        view.emote = "⚙️"
        view.emotePop = bouncing(speedHz: 1.2) * 0.4
        wanderStep()                              // still potters about while busy
    }

    private func beSleepy() {
        view.frameIndex = 0
        view.emote = "💤"
        view.emotePop = bouncing(speedHz: 0.6) * 0.4
        view.bob = sin(bobPhase * 1.1) * 1.2
    }

    private func beWander() {
        view.emote = nil
        view.emotePop = 0
        wanderStep()
    }

    /// The original target-seeking wander: walk to a random spot, pause, repeat.
    private func wanderStep() {
        if clock < pauseUntil {
            view.frameIndex = 0
            view.bob = sin(bobPhase * 2.2) * 1.5
            return
        }
        let dx = wanderTarget.x - center.x
        let dy = wanderTarget.y - center.y
        if hypot(dx, dy) <= arrive {
            pauseUntil = clock + CGFloat.random(in: 0.8...2.4)
            pickWanderTarget()
            return
        }
        walk(toward: wanderTarget)
    }

    /// Step `center` toward `p`, set the facing frame, and add a walking hop.
    private func walk(toward p: CGPoint) {
        let dx = p.x - center.x, dy = p.y - center.y
        let dist = hypot(dx, dy)
        guard dist > 0.5 else { return }
        let stepLen = min(speed * tick, dist)
        center.x += dx / dist * stepLen
        center.y += dy / dist * stepLen
        view.frameIndex = MascotSprite.frameIndex(headingDegrees: heading(to: p))
        view.bob = abs(sin(bobPhase * 7)) * 3
        applyCenter()
    }

    /// Movement heading toward `p`, in the screen-flipped degrees MascotSprite
    /// expects (y-down). Screen y is up in AppKit, so negate dy.
    private func heading(to p: CGPoint) -> Double {
        atan2(-(p.y - center.y), p.x - center.x) * 180 / .pi
    }

    private func bouncing(speedHz: CGFloat) -> CGFloat {
        (sin(bobPhase * speedHz * 2 * .pi) + 1) / 2
    }

    private func pickWanderTarget() {
        let area = visibleArea()
        let lowerTop = area.minY + area.height * 0.45   // stay near the "ground"
        wanderTarget = CGPoint(
            x: CGFloat.random(in: area.minX...area.maxX),
            y: CGFloat.random(in: area.minY...lowerTop))
    }

    private func endDrag() {
        center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        clampCenter(); applyCenter()
        pauseUntil = clock + 1.2
        lastInteract = clock
        pickWanderTarget()
        dragging = false
    }

    // MARK: - Bubble

    /// Position + show/hide the bubble panel above the mascot each tick.
    private func syncBubble() {
        let show = (message != nil) && clock < messageUntil
        if show, let message {
            if bubbleView.text != message {
                bubbleView.text = message
                let size = MascotBubbleView.size(for: message)
                bubblePanel.setContentSize(size)
            }
            let origin = NSPoint(
                x: center.x - bubblePanel.frame.width / 2,
                y: panel.frame.maxY - 4)
            bubblePanel.setFrameOrigin(clampBubble(origin))
            if !bubblePanel.isVisible { bubblePanel.orderFrontRegardless() }
        } else if bubblePanel.isVisible {
            bubblePanel.orderOut(nil)
        }
    }

    private func clampBubble(_ origin: NSPoint) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main
        else { return origin }
        let v = screen.visibleFrame
        var o = origin
        o.x = min(max(o.x, v.minX + 4), v.maxX - bubblePanel.frame.width - 4)
        // If it would clip the top of the screen, tuck it down a touch.
        o.y = min(o.y, v.maxY - bubblePanel.frame.height - 2)
        return o
    }

    private func setMessage(_ text: String, alert: Bool) {
        message = text
        messageUntil = clock + (alert ? 9 : 5)
        if alert { alertUntil = clock + 3.5 }
    }

    private func refreshBubbleForHover() {
        if let message {
            messageUntil = max(messageUntil, clock + 4)
            _ = message
        } else if agentID != nil {
            let running = runningProvider?() ?? false
            message = running ? "ทำงานอยู่… ⚙️" : "ว่างอยู่ 🌸"
            messageUntil = clock + 4
        }
    }

    /// Poll the agent's newest inbox line; speak it and perk up on a new message.
    private func pollMessages() {
        guard let agentID else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let snap = try? await BwocCli.shared.inbox(agent: agentID, limit: 1),
                  let msg = snap.messages.last else { return }
            if msg.messageId == self.lastMessageId { return }
            let isNew = self.seenFirstPoll
            self.lastMessageId = msg.messageId
            self.seenFirstPoll = true
            self.setMessage(Self.format(msg), alert: isNew)
        }
    }

    /// "from ▸ message", whitespace-collapsed and length-capped for the bubble.
    private static func format(_ msg: InboxMessage) -> String {
        let body = msg.message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = body.count > 140 ? String(body.prefix(139)) + "…" : body
        let from = msg.from == "user" ? "ที่รัก" : msg.from
        return "\(from) ▸ \(capped)"
    }

    // MARK: - Geometry

    private func visibleArea() -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.main ?? NSScreen.screens.first!
        let v = screen.visibleFrame
        return v.insetBy(dx: panel.frame.width / 2, dy: panel.frame.height / 2)
    }

    private func clampCenter() {
        let area = visibleArea()
        center.x = min(max(center.x, area.minX), area.maxX)
        center.y = min(max(center.y, area.minY), area.maxY)
    }

    private func applyCenter() {
        panel.setFrameOrigin(NSPoint(x: center.x - panel.frame.width / 2,
                                     y: center.y - panel.frame.height / 2))
    }
}
