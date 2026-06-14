import AppKit

/// One terminal window. Multiple windows group into native macOS tabs
/// (`tabbingIdentifier`), giving iTerm2-style tabs with system behavior.
final class TerminalWindowController: NSWindowController, NSWindowDelegate {
    let tabVC: TerminalTabViewController
    var onClose: ((TerminalWindowController) -> Void)?
    private var forceClose = false
    private var titleTimer: Timer?
    private var chromeObserver: NSObjectProtocol?
    private var appliedBlurRadius = 0

    init(profile: Profile, initialDirectory: String?) {
        tabVC = TerminalTabViewController(profile: profile, initialDirectory: initialDirectory)

        let font = resolvedFont(name: profile.fontName, size: CGFloat(profile.fontSize))
        let cell = terminalCellSize(font: font)
        let pad = CGFloat(profile.padding)
        let content = NSSize(
            width: CGFloat(max(40, profile.columns)) * cell.width + pad * 2,
            height: CGFloat(max(10, profile.rows)) * cell.height + pad * 2
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "iGhostty.terminal"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 280, height: 180)
        window.title = "iGhostty"
        window.contentViewController = tabVC
        window.setContentSize(content)

        super.init(window: window)
        window.delegate = self
        applyChrome(profile: profile)

        chromeObserver = NotificationCenter.default.addObserver(
            forName: .iGhosttySettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyChrome()
        }

        tabVC.onTitleChange = { [weak self] title in
            self?.window?.title = title
            self?.applyChrome() // active pane (and its profile) may have changed
        }
        tabVC.onLastPaneClosed = { [weak self] in
            guard let self else { return }
            self.forceClose = true
            self.window?.close()
        }

        // Keep "shell — directory" titles fresh even without OSC titles
        // (plain zsh emits none; we read the cwd via libproc).
        titleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let session = self.tabVC.activeSession else { return }
            let title = session.displayTitle
            if self.window?.title != title {
                self.window?.title = title
            }
        }
        titleTimer?.tolerance = 0.5
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Tints the title bar / window background to the active profile's scheme
    /// (so the top bar is never a bare default), and applies the window style
    /// (standard vs. compact-without-title-bar, like iTerm2's Minimal theme).
    func applyChrome(profile explicit: Profile? = nil) {
        guard let window else { return }
        let profile = explicit ?? tabVC.activeSession?.appliedProfile ?? SettingsStore.shared.defaultProfile

        let opacity = effectiveOpacity(for: profile)
        let transparentContent = opacity < 0.999
        window.backgroundColor = NSColor(profile.scheme.background).withAlphaComponent(opacity)
        window.isOpaque = !transparentContent
        window.appearance = NSAppearance(named: profile.scheme.isLight ? .aqua : .darkAqua)

        // Only touch the private window-server blur path when blur is actually
        // in use. Invoking it with radius 0 still enrolls the window in the
        // blurred-backdrop compositor, which can soften the window's own
        // content — so a window that never uses blur must never call it.
        let blurRadius = effectiveBlurRadius(for: profile)
        if blurRadius > 0 || appliedBlurRadius > 0 {
            WindowBlur.apply(to: window, radius: blurRadius)
            appliedBlurRadius = blurRadius
        }

        // Title bar: seamless themed bar when opaque or when the whole frame is
        // meant to be transparent; a standard opaque bar when the user unlinks
        // it (transparent content, solid top bar).
        let opaqueTitleBar = transparentContent && !profile.transparentTitleBar
        window.titlebarAppearsTransparent = !opaqueTitleBar

        switch SettingsStore.shared.settings.ui.windowStyle {
        case .regular:
            window.styleMask.remove(.fullSizeContentView)
            window.titleVisibility = .visible
        case .compact:
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
        }
        window.invalidateShadow()
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !forceClose else { return true }
        let running = tabVC.busySessionCount
        if running > 0, SettingsStore.shared.settings.ui.confirmQuit {
            let alert = NSAlert()
            alert.messageText = "Close this terminal window?"
            alert.informativeText = running == 1
                ? "A session is still running a job that will be terminated."
                : "\(running) sessions are still running jobs that will be terminated."
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: sender) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    self?.forceClose = true
                    sender.close()
                }
            }
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        titleTimer?.invalidate()
        titleTimer = nil
        if let chromeObserver {
            NotificationCenter.default.removeObserver(chromeObserver)
            self.chromeObserver = nil
        }
        tabVC.terminateAll()
        onClose?(self)
    }

    /// Called by the "+" button in the native tab bar.
    override func newWindowForTab(_ sender: Any?) {
        AppDelegate.shared?.newTab(self)
    }

    /// Close without the running-sessions confirmation (used when the whole
    /// tab group is being closed and the user already confirmed once).
    func forceCloseWindow() {
        forceClose = true
        window?.close()
    }
}
