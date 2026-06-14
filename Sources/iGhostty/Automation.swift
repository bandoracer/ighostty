import AppKit
import ServiceManagement

/// Headless test/automation channel, active only when the app is launched
/// with IGHOSTTY_AUTOMATION=1. Drives the UI and captures self-rendered
/// screenshots so the app can be exercised without Accessibility access.
///
/// Commands (posted as the object of the "iGhostty.automation" distributed
/// notification):
///   type:<text>        send text to the focused terminal ("\n" → newline)
///   splitV / splitH    split the active pane
///   newTab / newWindow
///   openSettings:<n>   open the settings window at tab n
///   toggleDropdown
///   snap:<directory>   capture every visible window to PNG files
extension AppDelegate {
    func installAutomationChannelIfRequested() {
        guard ProcessInfo.processInfo.environment["IGHOSTTY_AUTOMATION"] == "1" else { return }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleAutomationCommand(_:)),
            name: NSNotification.Name("iGhostty.automation"),
            object: nil,
            suspensionBehavior: .deliverImmediately // keep working while hidden
        )
        // Distributed-notification delivery gets suspended for deactivated
        // apps, so also poll a command file — that channel can't be paused
        // (and proves the run loop stays healthy while backgrounded).
        let commandURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("iGhostty-automation-cmd")
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let text = try? String(contentsOf: commandURL, encoding: .utf8) else { return }
            try? FileManager.default.removeItem(at: commandURL)
            for line in text.split(separator: "\n") where !line.isEmpty {
                Task { @MainActor in
                    self?.runAutomationCommand(String(line))
                }
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        NSLog("iGhostty automation channel enabled")
    }

    @objc func handleAutomationCommand(_ note: Notification) {
        guard let command = note.object as? String else { return }
        Task { @MainActor in
            self.runAutomationCommand(command)
        }
    }

    @MainActor
    func runAutomationCommand(_ command: String) {
        NSLog("iGhostty automation: %@", command)

        if command.hasPrefix("type:") {
            let payload = String(command.dropFirst(5))
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\r", with: "\r")
            if let session = automationTargetTabVC()?.activeSession {
                let bytes = [UInt8](payload.utf8)
                session.sendRaw(bytes[...])
            }
            return
        }
        if command.hasPrefix("openSettings:") {
            let idx = Int(command.dropFirst("openSettings:".count)) ?? 0
            showSettings(tabIndex: idx)
            return
        }
        if command.hasPrefix("snap:") {
            let dir = String(command.dropFirst(5))
            snapshotAllWindows(to: URL(fileURLWithPath: dir, isDirectory: true))
            return
        }
        if command.hasPrefix("shortcut:") {
            let key = String(command.dropFirst("shortcut:".count))
            performCommandShortcut(key)
            return
        }
        if command.hasPrefix("setScheme:") {
            // Live-recolor proof: mutate the default profile's scheme through
            // the store, exactly like the Settings UI does.
            let name = String(command.dropFirst("setScheme:".count))
            if let scheme = ColorScheme.builtIns.first(where: { $0.name == name }),
               let idx = store.settings.profiles.firstIndex(where: { $0.id == store.settings.defaultProfileID }) {
                store.settings.profiles[idx].scheme = scheme
            }
            return
        }
        if command.hasPrefix("windowStyle:") {
            let raw = String(command.dropFirst("windowStyle:".count))
            if let style = WindowStyle(rawValue: raw) {
                store.settings.ui.windowStyle = style
            }
            return
        }
        switch command {
        case "splitV": automationTargetTabVC()?.splitActiveSession(vertically: true)
        case "splitH": automationTargetTabVC()?.splitActiveSession(vertically: false)
        case "newTab": newTab(nil)
        case "newWindow": newWindow(nil)
        case "toggleDropdown": DropdownWindowController.shared.toggle()
        case "doubleTap": ModifierTapDetector.shared.simulateDoubleTap()
        case "testOptionSplits":
            // Verify ⌥V/⌥H through the real interception path: a synthetic
            // event bound to the window, with a terminal pane focused.
            guard let wc = windowControllers.first, let window = wc.window else { return }
            window.makeKeyAndOrderFront(nil)
            wc.tabVC.focusActiveSession()
            for (ch, base, code) in [("√", "v", UInt16(9)), ("˙", "h", UInt16(4))] {
                guard let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.option],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, characters: ch, charactersIgnoringModifiers: base,
                    isARepeat: false, keyCode: code
                ) else { continue }
                let handled = handleOptionShortcut(event)
                NSLog("iGhostty automation: option-%@ handled = %d, panes = %d",
                      base, handled ? 1 : 0, wc.tabVC.panes.count)
            }
        case let cmd where cmd.hasPrefix("setTransparency:"):
            if let v = Double(cmd.dropFirst("setTransparency:".count)),
               let idx = store.settings.profiles.firstIndex(where: { $0.id == store.settings.defaultProfileID }) {
                store.settings.profiles[idx].transparency = v
            }
        case let cmd where cmd.hasPrefix("setBlur:"):
            if let v = Double(cmd.dropFirst("setBlur:".count)),
               let idx = store.settings.profiles.firstIndex(where: { $0.id == store.settings.defaultProfileID }) {
                store.settings.profiles[idx].blurEnabled = v > 0
                store.settings.profiles[idx].blurRadius = v
            }
        case let cmd where cmd.hasPrefix("setTitleBarTransparent:"):
            if let idx = store.settings.profiles.firstIndex(where: { $0.id == store.settings.defaultProfileID }) {
                store.settings.profiles[idx].transparentTitleBar = cmd.hasSuffix(":1")
            }
        case let cmd where cmd.hasPrefix("setCursor:"):
            let raw = String(cmd.dropFirst("setCursor:".count))
            if let shape = CursorShape(rawValue: raw),
               let idx = store.settings.profiles.firstIndex(where: { $0.id == store.settings.defaultProfileID }) {
                store.settings.profiles[idx].cursorShape = shape
            }
        case let cmd where cmd.hasPrefix("setCursorBlink:"):
            if let idx = store.settings.profiles.firstIndex(where: { $0.id == store.settings.defaultProfileID }) {
                store.settings.profiles[idx].cursorBlink = cmd.hasSuffix(":1")
            }
        case let cmd where cmd.hasPrefix("setMetal:"):
            store.settings.ui.useMetalRenderer = true
            NSLog("iGhostty automation: renderer is always libghostty Metal")
        case "reportCursor":
            if let s = automationTargetTabVC()?.activeSession {
                let p = s.appliedProfile
                NSLog("iGhostty cursor report: profile.shape=%@ blink=%d | core=libghostty | metal=%d",
                      p.cursorShape.rawValue, p.cursorBlink ? 1 : 0,
                      s.termView.isUsingMetalRenderer ? 1 : 0)
            }
        case "reportGhosttyColors":
            if let s = automationTargetTabVC()?.activeSession {
                NSLog("iGhostty ghostty color config:\n%@", s.renderedGhosttyColorConfig)
            }
        case "dumpViewport":
            if let text = automationTargetTabVC()?.activeSession?.visibleTextSnapshot {
                NSLog("iGhostty viewport dump: %@", text)
            }
        case "broadcast": automationTargetTabVC()?.toggleBroadcast()
        case "maximize": automationTargetTabVC()?.toggleMaximizedPane()
        case "nextPane": automationTargetTabVC()?.focusNextPane(forward: true)
        case "restartSession": automationTargetTabVC()?.activeSession?.restart()
        case "editSession": editSession(nil)
        case "transparency": toggleUseTransparency(nil)
        case let cmd where cmd.hasPrefix("importITerm:"):
            let path = String(cmd.dropFirst("importITerm:".count))
            do {
                let imported = try ITermImport.importProfiles(from: URL(fileURLWithPath: path))
                store.settings.profiles.append(contentsOf: imported)
                NSLog("iGhostty automation: imported %d iTerm2 profiles: %@",
                      imported.count, imported.map(\.name).joined(separator: ", "))
            } catch {
                NSLog("iGhostty automation: import failed: %@", error.localizedDescription)
            }
        case "frames":
            for w in NSApp.windows where w.isVisible {
                NSLog("iGhostty frames: '%@' frame=%@ panel=%d", w.title, NSStringFromRect(w.frame), w is NSPanel ? 1 : 0)
            }
        case "quit":
            quitRequested(nil)
        case "quitCompletely":
            quitCompletely(nil)
        case "policyInfo":
            let policy: String
            switch NSApp.activationPolicy() {
            case .regular: policy = "regular"
            case .accessory: policy = "accessory"
            default: policy = "prohibited"
            }
            NSLog("iGhostty automation: policy=%@ regularWindows=%d dropdownVisible=%d",
                  policy, windowControllers.count, DropdownWindowController.shared.isVisible ? 1 : 0)
        case "loginItem:on", "loginItem:off":
            let agent = SMAppService.agent(plistName: "dev.ighostty.background.plist")
            do {
                if command.hasSuffix(":on") { try agent.register() } else { try agent.unregister() }
                NSLog("iGhostty automation: login agent status=%d", agent.status.rawValue)
            } catch {
                NSLog("iGhostty automation: login agent error: %@", error.localizedDescription)
            }
        case "activate":
            NSApp.activate(ignoringOtherApps: true)
            windowControllers.first?.window?.makeKeyAndOrderFront(nil)
        default:
            NSLog("iGhostty automation: unknown command %@", command)
        }
    }

    @MainActor
    private func automationTargetTabVC() -> TerminalTabViewController? {
        if let key = NSApp.keyWindow?.contentViewController as? TerminalTabViewController {
            return key
        }
        if DropdownWindowController.shared.isVisible, let vc = DropdownWindowController.shared.tabVC {
            return vc
        }
        return windowControllers.first?.tabVC
    }

    @MainActor
    private func snapshotAllWindows(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let windows = NSApp.windows.filter { $0.isVisible }

        for window in windows {
            let view = window.contentView?.superview ?? window.contentView
            view?.layoutSubtreeIfNeeded()
            view?.needsDisplay = true
            view?.displayIfNeeded()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            var index = 0
            for window in windows where window.isVisible {
                guard let image = CGWindowListCreateImage(
                    .null,
                    .optionIncludingWindow,
                    CGWindowID(window.windowNumber),
                    [.bestResolution, .boundsIgnoreFraming]
                ) else { continue }
                let rep = NSBitmapImageRep(cgImage: image)
                guard let png = rep.representation(using: .png, properties: [:]) else { continue }

                let slug = window.title.isEmpty
                    ? (window is NSPanel ? "dropdown" : "window")
                    : window.title.lowercased()
                        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
                let name = String(format: "%02d-%@.png", index, slug)
                try? png.write(to: directory.appendingPathComponent(name))
                index += 1
            }
            self?.automationLogSnapshotCount(index, directory: directory)
        }
    }

    @MainActor
    private func automationLogSnapshotCount(_ count: Int, directory: URL) {
        NSLog("iGhostty automation: wrote %d snapshots to %@", count, directory.path)
    }

    @MainActor
    private func performCommandShortcut(_ key: String) {
        guard let window = NSApp.keyWindow ?? windowControllers.first?.window else {
            NSLog("iGhostty automation: shortcut cmd-%@ handled = 0 (no key window)", key)
            return
        }
        window.makeKeyAndOrderFront(nil)
        window.contentViewController.flatMap { $0 as? TerminalTabViewController }?.focusActiveSession()

        let characters = shortcutCharacters(key)
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: shortcutKeyCode(key)
        ) else {
            NSLog("iGhostty automation: shortcut cmd-%@ handled = 0 (event creation failed)", key)
            return
        }

        let handled = window.performKeyEquivalent(with: event)
        NSLog("iGhostty automation: shortcut cmd-%@ handled = %d", key, handled ? 1 : 0)
    }

    private func shortcutCharacters(_ key: String) -> String {
        switch key {
        case "return": return "\r"
        case "tab": return "\t"
        case "space": return " "
        default: return key
        }
    }

    private func shortcutKeyCode(_ key: String) -> UInt16 {
        switch key.lowercased() {
        case "a": return 0
        case "c": return 8
        case "f": return 3
        case "n": return 45
        case "q": return 12
        case "t": return 17
        case "v": return 9
        case "w": return 13
        case ",": return 43
        default: return 0
        }
    }

    @MainActor
    private func terminalSessions(in window: NSWindow) -> [TerminalSessionView] {
        if let vc = window.contentViewController as? TerminalTabViewController {
            return vc.panes
        }
        return []
    }
}
