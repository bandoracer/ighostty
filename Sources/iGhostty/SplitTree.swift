import AppKit

enum PaneDirection {
    case left, right, up, down
}

/// The content of one tab (or the drop-down window): a tree of terminal panes
/// built from nested `NSSplitView`s, iTerm2-style.
final class TerminalTabViewController: NSViewController, TerminalSessionViewDelegate {
    private(set) var panes: [TerminalSessionView] = []
    private(set) weak var activeSession: TerminalSessionView?
    private(set) var broadcastEnabled = false
    private(set) weak var maximizedSession: TerminalSessionView?

    var onTitleChange: ((String) -> Void)?
    var onLastPaneClosed: (() -> Void)?

    private let initialProfile: Profile
    private let initialDirectory: String?
    private var settingsObserver: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var keyMonitor: Any?

    init(profile: Profile, initialDirectory: String?) {
        self.initialProfile = profile
        self.initialDirectory = initialDirectory
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let pane = makeSession(profile: initialProfile, directory: initialDirectory ?? NSHomeDirectory())
        install(root: pane)
        activeSession = pane

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .iGhosttySettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateInactivePaneEffects()
        }

        // Track pane activation by watching clicks land inside our panes.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handleMouseDown(event)
            return event
        }

        // Marks the focused pane's next send as keyboard input so broadcast
        // mode fans out keystrokes but not terminal query responses.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDownForBroadcast(event)
            return event
        }
    }

    private func handleKeyDownForBroadcast(_ event: NSEvent) {
        guard broadcastEnabled, event.window === view.window,
              let responder = view.window?.firstResponder as? SessionTerminalView,
              panes.contains(where: { $0.termView === responder }) else { return }
        responder.markUserInputPending()
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard event.window === view.window else { return }
        for pane in panes where pane !== activeSession {
            let p = pane.convert(event.locationInWindow, from: nil)
            if pane.bounds.contains(p) {
                sessionDidActivate(pane)
                return
            }
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        focusActiveSession()
    }

    // MARK: Session management

    private func makeSession(profile: Profile, directory: String?) -> TerminalSessionView {
        let session = TerminalSessionView(profile: profile)
        session.delegate = self
        session.start(initialDirectory: directory)
        panes.append(session)
        if broadcastEnabled {
            session.setBroadcasting(true, sink: { [weak self] data in self?.fanOut(data) })
        }
        return session
    }

    private func install(root: NSView) {
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        // Pin to the safe area so compact (full-size-content) windows keep the
        // terminal clear of the traffic-light strip.
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func focusActiveSession() {
        let target = activeSession ?? panes.first
        guard let target else { return }
        view.window?.makeFirstResponder(target.termView)
        sessionDidActivate(target)
    }

    var hasRunningSessions: Bool {
        panes.contains { !$0.processExited }
    }

    var runningSessionCount: Int {
        panes.filter { !$0.processExited }.count
    }

    /// Sessions actively running a job — what close/quit confirmations count.
    var busySessionCount: Int {
        panes.filter { $0.isBusy }.count
    }

    func terminateAll() {
        panes.forEach { $0.terminate() }
    }

    // MARK: Splitting

    /// `vertically: true` = side-by-side panes (vertical divider), matching iTerm2's ⌘D.
    func splitActiveSession(vertically: Bool) {
        restoreMaximizedPane()
        guard let active = activeSession ?? panes.first else { return }

        let profile = SettingsStore.shared.profile(withID: active.profileID) ?? active.appliedProfile
        let dir = startDirectory(for: profile, inheritingFrom: active)
        let newPane = makeSession(profile: profile, directory: dir)

        guard let host = active.superview else { return }
        let split = NSSplitView()
        split.isVertical = vertically
        split.dividerStyle = .thin

        if let parentSplit = host as? NSSplitView {
            guard let idx = parentSplit.arrangedSubviews.firstIndex(of: active) else { return }
            active.removeFromSuperview()
            parentSplit.insertArrangedSubview(split, at: idx)
        } else {
            active.removeFromSuperview()
            install(root: split)
        }

        split.addArrangedSubview(active)
        split.addArrangedSubview(newPane)
        view.layoutSubtreeIfNeeded()
        let total = vertically ? split.bounds.width : split.bounds.height
        if total > split.dividerThickness {
            split.setPosition((total - split.dividerThickness) / 2, ofDividerAt: 0)
        } else {
            split.adjustSubviews()
        }

        focus(newPane)
        updateInactivePaneEffects()
    }

    func closeSession(_ session: TerminalSessionView) {
        restoreMaximizedPane()
        session.terminate()
        panes.removeAll { $0 === session }

        defer {
            if panes.isEmpty {
                onLastPaneClosed?()
            } else {
                if activeSession === session || activeSession == nil {
                    activeSession = panes.last
                }
                focusActiveSession()
                updateInactivePaneEffects()
                notifyTitle()
            }
        }

        guard let split = session.superview as? NSSplitView else {
            session.removeFromSuperview()
            return
        }
        session.removeFromSuperview()

        // Collapse a split that now has a single child.
        if split.arrangedSubviews.count == 1 {
            let survivor = split.arrangedSubviews[0]
            if let parent = split.superview as? NSSplitView {
                guard let idx = parent.arrangedSubviews.firstIndex(of: split) else { return }
                survivor.removeFromSuperview()
                split.removeFromSuperview()
                parent.insertArrangedSubview(survivor, at: idx)
            } else {
                survivor.removeFromSuperview()
                split.removeFromSuperview()
                install(root: survivor)
            }
        }
    }

    func closeActiveSession() {
        guard let active = activeSession ?? panes.first else { return }
        closeSession(active)
    }

    func focus(_ session: TerminalSessionView) {
        view.window?.makeFirstResponder(session.termView)
        sessionDidActivate(session)
    }

    // MARK: Broadcast input (⌥⌘I)

    func toggleBroadcast() {
        broadcastEnabled.toggle()
        let sink: ((ArraySlice<UInt8>) -> Void)? = broadcastEnabled
            ? { [weak self] data in self?.fanOut(data) }
            : nil
        for pane in panes {
            pane.setBroadcasting(broadcastEnabled, sink: sink)
        }
    }

    private func fanOut(_ data: ArraySlice<UInt8>) {
        for pane in panes {
            pane.sendRaw(data)
        }
    }

    // MARK: Maximize active pane (⇧⌘↩)

    func toggleMaximizedPane() {
        if maximizedSession != nil {
            restoreMaximizedPane()
            return
        }
        guard panes.count > 1, let active = activeSession else { return }
        maximizedSession = active
        for pane in panes where pane !== active {
            pane.isHidden = true
        }
        collapseEmptySplits(in: view)
        focus(active)
    }

    func restoreMaximizedPane() {
        guard maximizedSession != nil else { return }
        maximizedSession = nil
        unhideAll(in: view)
        updateInactivePaneEffects()
    }

    /// An NSSplitView whose arranged subviews are all hidden still claims its
    /// space; hide such containers so the maximized pane gets everything.
    private func collapseEmptySplits(in root: NSView) {
        for sub in root.subviews {
            collapseEmptySplits(in: sub)
        }
        if let split = root as? NSSplitView {
            split.isHidden = split.arrangedSubviews.allSatisfy { $0.isHidden }
        }
    }

    private func unhideAll(in root: NSView) {
        for sub in root.subviews {
            unhideAll(in: sub)
        }
        if root is NSSplitView || root is TerminalSessionView {
            root.isHidden = false
        }
    }

    // MARK: Pane cycling (⌘] / ⌘[)

    func focusNextPane(forward: Bool) {
        let visible = panes.filter { !$0.isHidden }
        guard visible.count > 1 else { return }
        guard let active = activeSession, let idx = visible.firstIndex(where: { $0 === active }) else {
            if let first = visible.first { focus(first) }
            return
        }
        let next = visible[(idx + (forward ? 1 : visible.count - 1)) % visible.count]
        focus(next)
    }

    // MARK: Directional pane navigation (⌘⌥arrows)

    func focusAdjacentPane(_ direction: PaneDirection) {
        guard panes.count > 1, let active = activeSession else { return }
        let af = active.convert(active.bounds, to: view)

        var best: (pane: TerminalSessionView, score: CGFloat)?
        for pane in panes where pane !== active && !pane.isHidden {
            let pf = pane.convert(pane.bounds, to: view)
            let dx = pf.midX - af.midX
            let dy = pf.midY - af.midY // AppKit: +y is up

            let (forward, overlap): (CGFloat, CGFloat)
            switch direction {
            case .left:
                forward = -dx
                overlap = overlapLength(af.minY...af.maxY, pf.minY...pf.maxY)
            case .right:
                forward = dx
                overlap = overlapLength(af.minY...af.maxY, pf.minY...pf.maxY)
            case .up:
                forward = dy
                overlap = overlapLength(af.minX...af.maxX, pf.minX...pf.maxX)
            case .down:
                forward = -dy
                overlap = overlapLength(af.minX...af.maxX, pf.minX...pf.maxX)
            }
            guard forward > 1 else { continue }
            // Prefer panes that overlap our cross-axis; among those, the nearest.
            let score = forward - overlap * 0.01
            if best == nil || score < best!.score {
                best = (pane, score)
            }
        }
        if let best { focus(best.pane) }
    }

    private func overlapLength(_ a: ClosedRange<CGFloat>, _ b: ClosedRange<CGFloat>) -> CGFloat {
        max(0, min(a.upperBound, b.upperBound) - max(a.lowerBound, b.lowerBound))
    }

    // MARK: Inactive pane effects

    func updateInactivePaneEffects() {
        let ui = SettingsStore.shared.settings.ui
        let shouldDesaturate = ui.desaturateInactivePanes && panes.count > 1
        for pane in panes {
            pane.setDesaturated(shouldDesaturate && pane !== activeSession, amount: ui.desaturationAmount)
        }
    }

    private func notifyTitle() {
        if let active = activeSession {
            onTitleChange?(active.displayTitle)
        }
    }

    // MARK: TerminalSessionViewDelegate

    func sessionTitleDidChange(_ session: TerminalSessionView) {
        if session === activeSession { notifyTitle() }
    }

    func sessionDidActivate(_ session: TerminalSessionView) {
        activeSession = session
        updateInactivePaneEffects()
        notifyTitle()
    }

    func sessionProcessDidTerminate(_ session: TerminalSessionView, exitCode: Int32?) {
        // Close behavior is handled via sessionRequestsClose.
    }

    func sessionRequestsClose(_ session: TerminalSessionView) {
        closeSession(session)
    }
}
