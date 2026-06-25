import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    static private(set) var shared: AppDelegate?

    let store = SettingsStore.shared
    private(set) var windowControllers: [TerminalWindowController] = []
    private var settingsWindowController: SettingsWindowController?
    private var cascadePoint = NSPoint.zero
    private var settingsObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var optionShortcutMonitor: Any?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    // MARK: Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A terminal must not be App-Napped: timers, the background hotkey
        // service, and PTY output handling all need a live run loop even
        // when the app has no windows and isn't frontmost.
        UserDefaults.standard.set(true, forKey: "NSAppSleepDisabled")
        // No state restoration — also keeps quit paths free of review dialogs.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenuBuilder.build(delegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let backgroundLaunch = CommandLine.arguments.contains("--background")
        if backgroundLaunch, !runningPeerApplications().isEmpty {
            NSLog("iGhostty background login item exiting because another iGhostty instance is already running")
            exit(0)
        }
        if !backgroundLaunch {
            terminateBackgroundPeerApplications()
            DispatchQueue.global(qos: .utility).async {
                LoginItemService.refreshRegistrationIfNeeded()
            }
        }

        applyTheme()
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshAppearanceDependentSurfaces()
            }
        }
        installAutomationChannelIfRequested()
        _ = AppUpdater.shared
        HotkeyManager.shared.handler = { DropdownWindowController.shared.toggle() }
        applyHotkeyRegistration()

        // ⌥V / ⌥H split shortcuts: macOS treats option+letter as typing, so
        // these never reach menu key-equivalent matching — intercept the key
        // events before the terminal view consumes them.
        optionShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            (self?.handleOptionShortcut(event) == true) ? nil : event
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .iGhosttySettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyTheme()
            self?.applyHotkeyRegistration()
            self?.refreshAppearanceDependentSurfaces()
        }

        if backgroundLaunch {
            // Login-item launch: no windows, no Dock icon — just the
            // drop-down terminal service waiting on its hotkey.
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            newWindow(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keep running for the drop-down hotkey, like iTerm2's hotkey window
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching/clicking the app while it idles in the background brings
        // back the Dock icon and opens a regular window.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        endBackgroundActivityIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        if !flag {
            if let wc = windowControllers.first {
                wc.window?.makeKeyAndOrderFront(nil)
            } else {
                newWindow(nil)
            }
        }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Toggle Drop-down Terminal", action: #selector(toggleDropdown(_:)), keyEquivalent: "")
        return menu
    }

    /// ⌘Q — with the background drop-down enabled this only closes windows;
    /// otherwise it quits. Deliberately avoids NSApp.terminate: AppKit's
    /// pre-quit document review can wedge in a nested run loop.
    @objc func quitRequested(_ sender: Any?) {
        NSLog(
            "iGhostty quit requested backgroundMode=%@ windows=%d",
            keepsDropdownAvailableInBackground ? "true" : "false",
            windowControllers.count
        )
        if keepsDropdownAvailableInBackground {
            _ = backgroundQuit()
        } else {
            quitCompletely(sender)
        }
    }

    /// ⌥⌘Q — actually quit, taking the drop-down terminal and any peer
    /// background service with it.
    @objc func quitCompletely(_ sender: Any?) {
        NSLog("iGhostty full quit requested")
        guard confirmFullShutdown(actionTitle: "Quit iGhostty completely?", buttonTitle: "Quit") else { return }
        shutdownAndExit(terminatePeers: true)
    }

    @objc func restartCompletely(_ sender: Any?) {
        NSLog("iGhostty restart requested")
        guard confirmFullShutdown(actionTitle: "Restart iGhostty completely?", buttonTitle: "Restart") else { return }
        launchSelfAfterExit()
        shutdownAndExit(terminatePeers: true)
    }

    private func confirmFullShutdown(actionTitle: String, buttonTitle: String) -> Bool {
        var busy = windowControllers.reduce(0) { $0 + $1.tabVC.busySessionCount }
        busy += DropdownWindowController.shared.tabVC?.busySessionCount ?? 0

        if store.settings.ui.confirmQuit, busy > 0 {
            let alert = NSAlert()
            alert.messageText = actionTitle
            alert.informativeText = (busy == 1
                ? "A session is still running a job that will be terminated."
                : "\(busy) sessions are still running jobs that will be terminated.")
                + " The drop-down terminal and any background iGhostty process will stop too."
            alert.addButton(withTitle: buttonTitle)
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        return true
    }

    private func shutdownAndExit(terminatePeers: Bool = false) -> Never {
        store.saveNow()
        if terminatePeers {
            terminatePeerApplications(includeRegular: true)
        }
        windowControllers.forEach { $0.tabVC.terminateAll() }
        DropdownWindowController.shared.terminateAll()
        exit(0)
    }

    private func launchSelfAfterExit() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "sleep 1; /usr/bin/open \"$1\"",
            "ighostty-restart",
            bundleURL.path,
        ]
        do {
            try process.run()
        } catch {
            NSLog("iGhostty failed to schedule restart: %@", error.localizedDescription)
        }
    }

    /// Reached by AppKit termination requests such as Dock Quit. Keep the
    /// drop-down service alive when background mode is enabled; explicit full
    /// quit/restart uses `shutdownAndExit` directly.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        NSLog(
            "iGhostty applicationShouldTerminate backgroundMode=%@ windows=%d",
            keepsDropdownAvailableInBackground ? "true" : "false",
            windowControllers.count
        )
        if keepsDropdownAvailableInBackground {
            _ = backgroundQuit(showDockQuitNotice: true)
            NSLog("iGhostty applicationShouldTerminate cancelled for background hotkey service")
            return .terminateCancel
        }

        store.saveNow()
        windowControllers.forEach { $0.tabVC.terminateAll() }
        DropdownWindowController.shared.terminateAll()
        return .terminateNow
    }

    /// ⌘Q with the background drop-down enabled: close the terminal windows,
    /// drop the Dock icon, keep the process (and the drop-down sessions) alive.
    private func backgroundQuit(showDockQuitNotice: Bool = false) -> Bool {
        let running = windowControllers.reduce(0) { $0 + $1.tabVC.busySessionCount }
        NSLog(
            "iGhostty background quit requested runningSessions=%d settingsWindowVisible=%@ notice=%@",
            running,
            settingsWindowController?.window?.isVisible == true ? "true" : "false",
            showDockQuitNotice ? "true" : "false"
        )
        if store.settings.ui.confirmQuit, running > 0 {
            let alert = NSAlert()
            alert.messageText = "Close all terminal windows?"
            alert.informativeText = (running == 1
                ? "A running session will be terminated."
                : "\(running) running sessions will be terminated.")
                + " iGhostty stays available in the background - the drop-down terminal keeps its sessions. Quit completely with ⌥⌘Q."
            alert.addButton(withTitle: "Close Windows")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }

        settingsWindowController?.close()
        windowControllers.forEach { $0.forceCloseWindow() }
        DropdownWindowController.shared.hide()

        if showDockQuitNotice {
            showDockQuitBackgroundNoticeIfNeeded()
        }

        NSApp.setActivationPolicy(.accessory)

        // Keep the hotkey service responsive: exempt the now-invisible app
        // from App Nap while it waits in the background.
        if backgroundActivity == nil {
            backgroundActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Drop-down terminal hotkey service"
            )
        }
        return true
    }

    private var backgroundActivity: NSObjectProtocol?

    func endBackgroundActivityIfNeeded() {
        if let backgroundActivity {
            ProcessInfo.processInfo.endActivity(backgroundActivity)
            self.backgroundActivity = nil
        }
    }


    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
        windowControllers.forEach { $0.tabVC.terminateAll() }
        DropdownWindowController.shared.terminateAll()
    }

    // MARK: Helpers

    /// The tab content of whichever window is key — terminal windows and the
    /// drop-down panel both expose a `TerminalTabViewController`.
    func keyTabViewController() -> TerminalTabViewController? {
        if let key = NSApp.keyWindow, let vc = key.contentViewController as? TerminalTabViewController {
            return vc
        }
        if let main = NSApp.mainWindow, let vc = main.contentViewController as? TerminalTabViewController {
            return vc
        }
        return nil
    }

    private func keyTerminalWindowController() -> TerminalWindowController? {
        if let key = NSApp.keyWindow, let wc = windowControllers.first(where: { $0.window === key }) {
            return wc
        }
        if let main = NSApp.mainWindow, let wc = windowControllers.first(where: { $0.window === main }) {
            return wc
        }
        return windowControllers.first { $0.window?.isVisible == true }
    }

    private var keepsDropdownAvailableInBackground: Bool {
        let hotkey = store.settings.hotkey
        return hotkey.enabled && hotkey.keepAvailableInBackground
    }

    private func showDockQuitBackgroundNoticeIfNeeded() {
        guard store.settings.ui.showDockQuitBackgroundNotice else { return }

        let alert = NSAlert()
        alert.messageText = "iGhostty is still running"
        alert.informativeText = "The drop-down terminal remains available in the background. Use Quit iGhostty Completely or Restart iGhostty Completely when you want to stop the background process too."
        alert.addButton(withTitle: "OK")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't show again"
        alert.runModal()

        if alert.suppressionButton?.state == .on {
            store.settings.ui.showDockQuitBackgroundNotice = false
            store.saveNow()
        }
    }

    private func runningPeerApplications() -> [NSRunningApplication] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != ownPID && !$0.isTerminated }
    }

    private func terminateBackgroundPeerApplications() {
        terminatePeerApplications(includeRegular: false)
    }

    private func terminatePeerApplications(includeRegular: Bool) {
        let peers = runningPeerApplications().filter { includeRegular || $0.activationPolicy != .regular }
        for app in peers {
            NSLog("iGhostty terminating peer pid=%d", app.processIdentifier)
            if !app.terminate() {
                app.forceTerminate()
            }
        }

        guard !peers.isEmpty else { return }
        let deadline = Date().addingTimeInterval(0.75)
        while Date() < deadline, peers.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        for app in peers where !app.isTerminated {
            NSLog("iGhostty force terminating peer pid=%d", app.processIdentifier)
            app.forceTerminate()
        }
    }

    private func track(_ wc: TerminalWindowController) {
        wc.onClose = { [weak self] closed in
            self?.windowControllers.removeAll { $0 === closed }
        }
        windowControllers.append(wc)
    }

    /// Creating a regular window must bring the app out of background mode —
    /// otherwise (e.g. ⌘N from the drop-down) the window has no Dock icon.
    private func ensureRegularActivation() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        endBackgroundActivityIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
    }

    func openWindow(profile: Profile) {
        ensureRegularActivation()
        let dir = startDirectory(for: profile, inheritingFrom: keyTabViewController()?.activeSession)
        let wc = TerminalWindowController(profile: profile, initialDirectory: dir)
        track(wc)
        if let window = wc.window {
            if windowControllers.count == 1 {
                window.center()
            } else {
                cascadePoint = window.cascadeTopLeft(from: cascadePoint)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    func openTab(profile: Profile, in host: TerminalWindowController?) {
        guard let host = host ?? keyTerminalWindowController(), let hostWindow = host.window else {
            openWindow(profile: profile)
            return
        }
        ensureRegularActivation()
        let dir = startDirectory(for: profile, inheritingFrom: host.tabVC.activeSession)
        let wc = TerminalWindowController(profile: profile, initialDirectory: dir)
        track(wc)
        if let window = wc.window {
            hostWindow.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Actions — Shell

    @objc func newWindow(_ sender: Any?) {
        openWindow(profile: store.defaultProfile)
    }

    @objc func newTab(_ sender: Any?) {
        let host = (sender as? TerminalWindowController) ?? keyTerminalWindowController()
        openTab(profile: store.defaultProfile, in: host)
    }

    @objc func newTabWithProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let profile = store.profile(withID: id) else { return }
        if keyTerminalWindowController() != nil {
            openTab(profile: profile, in: nil)
        } else {
            openWindow(profile: profile)
        }
    }

    /// Handles ⌥V / ⌥H splits when a terminal pane is focused. Returns true
    /// when the event was consumed (other ⌥ combos pass through as Meta).
    func handleOptionShortcut(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard mods == [.option],
              let window = event.window,
              window.firstResponder is SessionTerminalView,
              let tabVC = window.contentViewController as? TerminalTabViewController else { return false }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v":
            tabVC.splitActiveSession(vertically: true)
            return true
        case "h":
            tabVC.splitActiveSession(vertically: false)
            return true
        default:
            return false
        }
    }

    @objc func splitVertically(_ sender: Any?) {
        keyTabViewController()?.splitActiveSession(vertically: true)
    }

    @objc func splitHorizontally(_ sender: Any?) {
        keyTabViewController()?.splitActiveSession(vertically: false)
    }

    @objc func closeActive(_ sender: Any?) {
        guard let key = NSApp.keyWindow else { return }
        if let vc = key.contentViewController as? TerminalTabViewController, vc.panes.count > 1 {
            vc.closeActiveSession()
        } else if key is NSPanel {
            DropdownWindowController.shared.hide()
        } else {
            key.performClose(sender)
        }
    }

    // MARK: Actions — Edit/View

    @objc func clearBuffer(_ sender: Any?) {
        keyTabViewController()?.activeSession?.clearBuffer()
    }

    @objc func findPanelAction(_ sender: Any?) {
        Task { @MainActor in
            keyTabViewController()?.activeSession?.termView.performFindPanelAction(sender)
        }
    }

    @objc func biggerText(_ sender: Any?) {
        keyTabViewController()?.activeSession?.adjustFontSize(by: 1)
    }

    @objc func smallerText(_ sender: Any?) {
        keyTabViewController()?.activeSession?.adjustFontSize(by: -1)
    }

    @objc func resetTextSize(_ sender: Any?) {
        keyTabViewController()?.activeSession?.resetFontSize()
    }

    @objc func toggleDropdown(_ sender: Any?) {
        DropdownWindowController.shared.toggle()
    }

    // MARK: Actions — iTerm2-default shortcuts

    /// ⌘I — open Settings → Profiles with the active session's profile selected.
    @objc func editSession(_ sender: Any?) {
        let profileID = keyTabViewController()?.activeSession?.profileID
        let target = store.profile(withID: profileID)?.id ?? store.settings.defaultProfileID
        showSettings(tabIndex: 1)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .iGhosttySelectProfile, object: target)
        }
    }

    /// ⌥⌘I — type into every pane in the tab at once.
    @objc func toggleBroadcastInput(_ sender: Any?) {
        keyTabViewController()?.toggleBroadcast()
    }

    /// ⇧⌘↩ — temporarily give the active pane the whole tab.
    @objc func toggleMaximizePane(_ sender: Any?) {
        keyTabViewController()?.toggleMaximizedPane()
    }

    /// ⌘U — global transparency on/off without touching profiles.
    @objc func toggleUseTransparency(_ sender: Any?) {
        store.settings.ui.useTransparency.toggle()
    }

    /// ⌘] / ⌘[
    @objc func selectNextPane(_ sender: Any?) {
        keyTabViewController()?.focusNextPane(forward: true)
    }

    @objc func selectPreviousPane(_ sender: Any?) {
        keyTabViewController()?.focusNextPane(forward: false)
    }

    /// ⌘1…⌘9 — native tab selection by index.
    @objc func selectTabNumber(_ sender: NSMenuItem) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let group = window.tabGroup else { return }
        let index = sender.tag - 1
        guard index >= 0, index < group.windows.count else { return }
        let target = group.windows[index]
        group.selectedWindow = target
        target.makeKeyAndOrderFront(nil)
    }

    /// Shell → Restart Session (enabled once the process has exited).
    @objc func restartSession(_ sender: Any?) {
        keyTabViewController()?.activeSession?.restart()
    }

    @objc func jumpToPreviousPrompt(_ sender: Any?) {
        keyTabViewController()?.activeSession?.performGhosttyAction("jump_to_prompt:-1")
    }

    @objc func jumpToNextPrompt(_ sender: Any?) {
        keyTabViewController()?.activeSession?.performGhosttyAction("jump_to_prompt:1")
    }

    /// ⌥⌘W — close the whole tab (all panes), with the usual confirmation.
    @objc func closeAllPanesInTab(_ sender: Any?) {
        keyTerminalWindowController()?.window?.performClose(sender)
    }

    /// ⇧⌘W — close the window including every tab in its group.
    @objc func closeWholeWindow(_ sender: Any?) {
        guard let keyWC = keyTerminalWindowController(), let window = keyWC.window else { return }
        let group = window.tabGroup?.windows ?? [window]
        let controllers = windowControllers.filter { wc in group.contains(where: { $0 === wc.window }) }
        let running = controllers.reduce(0) { $0 + $1.tabVC.busySessionCount }

        if running > 1, store.settings.ui.confirmQuit {
            let alert = NSAlert()
            alert.messageText = group.count > 1 ? "Close this window and its \(group.count) tabs?" : "Close this window?"
            alert.informativeText = "\(running) running sessions will be terminated."
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        controllers.forEach { $0.forceCloseWindow() }
    }

    /// ⌘Home / ⌘End
    @objc func scrollToTop(_ sender: Any?) {
        Task { @MainActor in
            keyTabViewController()?.activeSession?.termView.scroll(toPosition: 0)
        }
    }

    @objc func scrollToEnd(_ sender: Any?) {
        Task { @MainActor in
            keyTabViewController()?.activeSession?.termView.scroll(toPosition: 1)
        }
    }

    @objc func selectPane(_ sender: NSMenuItem) {
        guard let dir = sender.representedObject as? String else { return }
        let direction: PaneDirection
        switch dir {
        case "up": direction = .up
        case "down": direction = .down
        case "left": direction = .left
        default: direction = .right
        }
        keyTabViewController()?.focusAdjacentPane(direction)
    }

    // MARK: Actions — App

    @objc func showSettings(_ sender: Any?) {
        showSettings(tabIndex: nil)
    }

    @MainActor @objc func checkForUpdates(_ sender: Any?) {
        AppUpdater.shared.checkForUpdates(sender)
    }

    @objc func toggleSecureKeyboardEntry(_ sender: Any?) {
        SecureInputManager.shared.toggleManual()
    }

    @objc func showProfileSettings(_ sender: Any?) {
        showSettings(tabIndex: 1)
    }

    func showSettings(tabIndex: Int?) {
        NSLog(
            "iGhostty settings open requested tab=%@ activationPolicy=%@",
            tabIndex.map(String.init) ?? "nil",
            String(describing: NSApp.activationPolicy())
        )
        ensureRegularActivation()
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: store)
        }
        settingsWindowController?.show(tabIndex: tabIndex)
        NSLog(
            "iGhostty settings window shown visible=%@ key=%@ activationPolicy=%@",
            settingsWindowController?.window?.isVisible == true ? "true" : "false",
            settingsWindowController?.window?.isKeyWindow == true ? "true" : "false",
            String(describing: NSApp.activationPolicy())
        )
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString(
            string: "An iTerm2-style terminal on libghostty.\nVT/emulation & GPU renderer: GhosttyTerminal / libghostty.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationVersion: appVersion,
        ])
    }

    @objc func openReadme(_ sender: Any?) {
        let candidates = [
            Bundle.main.url(forResource: "README", withExtension: "md"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("README.md"),
        ]
        for url in candidates.compactMap({ $0 }) where FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
            return
        }
    }

    @objc func revealSettingsFolder(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    // MARK: Settings application

    private func applyTheme() {
        switch store.settings.ui.theme {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func refreshAppearanceDependentSurfaces() {
        windowControllers.forEach { $0.applyChrome() }
        DropdownWindowController.shared.settingsDidChange()
    }

    func applyHotkeyRegistration() {
        let hk = store.settings.hotkey

        HotkeyManager.shared.updateRegistration(
            enabled: hk.enabled && hk.activationMode == .shortcut,
            keyCode: UInt32(hk.keyCode),
            carbonModifiers: carbonModifiers(from: NSEvent.ModifierFlags(rawValue: hk.modifierFlags))
        )

        if hk.enabled, hk.activationMode == .doubleTapModifier {
            ModifierTapDetector.shared.handler = { DropdownWindowController.shared.toggle() }
            ModifierTapDetector.shared.start(modifier: NSEvent.ModifierFlags(rawValue: hk.doubleTapModifier))
            promptAccessibilityIfNeeded()
        } else {
            ModifierTapDetector.shared.stop()
        }
    }

    /// System-wide double-tap detection needs Accessibility access (same as
    /// iTerm2's modifier double-tap). Auto-prompt at most once ever — after
    /// that, the Grant button in Settings → Hotkey Window is the explicit
    /// path. The in-app double-tap works without the permission either way.
    private func promptAccessibilityIfNeeded() {
        guard ProcessInfo.processInfo.environment["IGHOSTTY_AUTOMATION"] != "1",
              !AccessibilityPermission.isGranted else { return }
        let promptedKey = "didOfferAccessibilityPrompt"
        guard !UserDefaults.standard.bool(forKey: promptedKey) else { return }
        UserDefaults.standard.set(true, forKey: promptedKey)
        AccessibilityPermission.request()
    }

    // MARK: Dynamic menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.identifier == MenuID.profilesMenu || menu.identifier == MenuID.newTabProfileMenu else { return }
        menu.removeAllItems()
        for profile in store.settings.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(newTabWithProfile(_:)), keyEquivalent: "")
            item.representedObject = profile.id
            if profile.id == store.settings.defaultProfileID {
                item.state = .on
            }
            menu.addItem(item)
        }
        if menu.identifier == MenuID.profilesMenu {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Edit Profiles…", action: #selector(showProfileSettings(_:)), keyEquivalent: "o")
        }
    }

    // MARK: Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdates(_:)):
            return AppUpdater.shared.canCheckForUpdates
        case #selector(splitVertically(_:)), #selector(splitHorizontally(_:)),
             #selector(clearBuffer(_:)), #selector(findPanelAction(_:)),
             #selector(biggerText(_:)), #selector(smallerText(_:)),
             #selector(resetTextSize(_:)), #selector(selectPane(_:)),
             #selector(editSession(_:)), #selector(scrollToTop(_:)), #selector(scrollToEnd(_:)),
             #selector(jumpToPreviousPrompt(_:)), #selector(jumpToNextPrompt(_:)):
            return keyTabViewController() != nil
        case #selector(toggleSecureKeyboardEntry(_:)):
            menuItem.state = SecureInputManager.shared.isManualEnabled ? .on : .off
            return true
        case #selector(toggleBroadcastInput(_:)):
            menuItem.state = keyTabViewController()?.broadcastEnabled == true ? .on : .off
            return keyTabViewController() != nil
        case #selector(toggleMaximizePane(_:)):
            guard let vc = keyTabViewController() else { return false }
            menuItem.state = vc.maximizedSession != nil ? .on : .off
            return vc.panes.count > 1 || vc.maximizedSession != nil
        case #selector(toggleUseTransparency(_:)):
            menuItem.state = store.settings.ui.useTransparency ? .on : .off
            return true
        case #selector(selectNextPane(_:)), #selector(selectPreviousPane(_:)):
            return (keyTabViewController()?.panes.count ?? 0) > 1
        case #selector(restartSession(_:)):
            return keyTabViewController()?.activeSession?.processExited == true
        case #selector(closeAllPanesInTab(_:)), #selector(closeWholeWindow(_:)):
            return keyTerminalWindowController() != nil
        case #selector(closeActive(_:)):
            return NSApp.keyWindow != nil
        default:
            return true
        }
    }
}
