import AppKit
import CoreImage
import GhosttyTerminal
import UserNotifications

protocol TerminalSessionViewDelegate: AnyObject {
    func sessionTitleDidChange(_ session: TerminalSessionView)
    func sessionDidActivate(_ session: TerminalSessionView)
    func sessionProcessDidTerminate(_ session: TerminalSessionView, exitCode: Int32?)
    func sessionRequestsClose(_ session: TerminalSessionView)
}

final class SessionTerminalView: TerminalView {
    var onHostInput: ((Data) -> Void)?
    var onActivate: (() -> Void)?
    var broadcastSink: ((ArraySlice<UInt8>) -> Void)?
    private var userInputPending = false

    var isUsingMetalRenderer: Bool { true }

    func markUserInputPending() {
        userInputPending = true
        DispatchQueue.main.async { [weak self] in self?.userInputPending = false }
    }

    func send(txt: String) {
        sendText(txt)
    }

    func setUseMetal(_ enabled: Bool) throws {
        // libghostty's AppKit surface is Metal-backed. This method keeps the
        // automation/testing API compatible with the original app.
    }

    override func keyDown(with event: NSEvent) {
        markUserInputPending()
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if performMainMenuKeyEquivalent(with: event) {
            return true
        }
        markUserInputPending()
        return super.performKeyEquivalent(with: event)
    }

    private func performMainMenuKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard event.modifierFlags.contains(.command) else { return false }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) == true
    }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onActivate?()
        super.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onActivate?()
        super.otherMouseDown(with: event)
    }

    func routeHostInput(_ data: Data) {
        if userInputPending, let sink = broadcastSink {
            userInputPending = false
            let bytes = [UInt8](data)
            sink(bytes[...])
        } else {
            onHostInput?(data)
        }
    }

    func performFindPanelAction(_ sender: Any?) {
        let action = (sender as? NSMenuItem)
            .flatMap { NSFindPanelAction(rawValue: UInt($0.tag)) } ?? .showFindPanel
        switch action {
        case .showFindPanel:
            _ = performBindingAction("start_search")
        case .next:
            _ = performBindingAction("navigate_search:next")
        case .previous:
            _ = performBindingAction("navigate_search:previous")
        case .setFindString:
            _ = performBindingAction("search_selection")
        default:
            _ = performBindingAction("start_search")
        }
    }

    func scroll(toPosition position: Int) {
        _ = performBindingAction(position == 0 ? "scroll_to_top" : "scroll_to_bottom")
    }
}

private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class TerminalSessionView: NSView,
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceGridResizeDelegate,
    TerminalSurfaceBellDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfacePwdDelegate,
    TerminalSurfaceProgressReportDelegate,
    TerminalSurfaceCommandFinishedDelegate,
    TerminalSurfaceDesktopNotificationDelegate,
    TerminalSurfaceOpenURLDelegate,
    TerminalSurfaceHoverLinkDelegate,
    TerminalSurfaceTextSelectionRequestDelegate
{
    let termView: SessionTerminalView
    private let flashView = PassthroughView()
    private let secureInputIndicator = NSImageView()

    private(set) var appliedProfile: Profile
    private(set) var terminalTitle = ""
    private(set) var osc7Directory: String?
    private(set) var lastCommandExitCode: Int?
    private(set) var lastCommandDurationNanos: UInt64?
    private(set) var progressState: TerminalProgressState?
    private(set) var progressPercent: Int?
    private(set) var hasStarted = false
    private(set) var processExited = false
    private var fontDelta: CGFloat = 0
    private var shellDisplayName = "shell"
    private var settingsObserver: NSObjectProtocol?
    private var secureInputObserver: NSObjectProtocol?
    private var appliedTransparencyFlag = true
    private var startDirectoryUsed: String?
    private var startupGeneration = 0
    private var inactiveSaturation = 1.0

    private lazy var ghosttySession = InMemoryTerminalSession(
        write: { [weak self] data in
            DispatchQueue.main.async {
                self?.termView.routeHostInput(data)
            }
        },
        resize: { [weak self] viewport in
            let columns = Int(viewport.columns)
            let rows = Int(viewport.rows)
            Task { @MainActor in
                self?.ptySession?.resize(columns: columns, rows: rows)
            }
        }
    )
    private var terminalController: TerminalController!
    private var ptySession: LocalPTYSession?

    weak var delegate: TerminalSessionViewDelegate?

    var profileID: UUID { appliedProfile.id }

    init(profile: Profile) {
        self.appliedProfile = profile
        self.termView = SessionTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        wantsLayer = true

        addSubview(termView)

        flashView.wantsLayer = true
        flashView.layer?.backgroundColor = NSColor.white.cgColor
        flashView.alphaValue = 0
        addSubview(flashView)

        secureInputIndicator.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure Keyboard Entry")
        secureInputIndicator.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        secureInputIndicator.contentTintColor = .systemYellow
        secureInputIndicator.toolTip = "Secure Keyboard Entry is active"
        secureInputIndicator.isHidden = true
        addSubview(secureInputIndicator)

        termView.delegate = self
        termView.onActivate = { [weak self] in
            guard let self else { return }
            self.delegate?.sessionDidActivate(self)
        }
        termView.onHostInput = { [weak self] data in
            self?.ptySession?.send(data)
        }
        termView.configuration = TerminalSurfaceOptions(backend: .inMemory(ghosttySession))
        terminalController = TerminalController(
            configuration: ghosttyTerminalConfiguration(for: profile),
            theme: ghosttyTheme(for: profile)
        )
        terminalController.setColorScheme(ghosttyColorScheme(for: currentAppearanceVariant()))
        termView.controller = terminalController
        termView.setAccessibilityElement(true)
        termView.setAccessibilityIdentifier("terminal.surface")
        termView.setAccessibilityLabel("Terminal Surface")

        apply(profile, force: true)

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .iGhosttySettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reapplyFromStore()
            self?.updateSecureInputIndicator()
        }
        secureInputObserver = NotificationCenter.default.addObserver(
            forName: .iGhosttySecureInputChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateSecureInputIndicator()
        }
        updateSecureInputIndicator()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        if let secureInputObserver { NotificationCenter.default.removeObserver(secureInputObserver) }
    }

    override func layout() {
        super.layout()
        flashView.frame = bounds
        secureInputIndicator.frame = NSRect(x: bounds.maxX - 26, y: bounds.maxY - 26, width: 18, height: 18)
        let pad = CGFloat(appliedProfile.padding)
        termView.frame = bounds.insetBy(dx: pad, dy: pad)
        termView.fitToSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        termView.fitToSize()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply(appliedProfile, force: true)
        if let controller = window?.windowController as? TerminalWindowController {
            controller.applyChrome()
        } else {
            DropdownWindowController.shared.settingsDidChange()
        }
    }

    // MARK: Process lifecycle

    func start(initialDirectory: String?) {
        guard !hasStarted else { return }
        hasStarted = true
        processExited = false
        startupGeneration += 1

        let profile = appliedProfile
        let generation = startupGeneration
        let shellPath = profile.customShellPath.isEmpty ? defaultShellPath() : profile.customShellPath.expandingTilde
        shellDisplayName = (shellPath as NSString).lastPathComponent

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "NO_COLOR")
        if env["CLICOLOR"] == "0" {
            env.removeValue(forKey: "CLICOLOR")
        }
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        for (k, v) in profile.environmentDictionary { env[k] = v }
        let launch = GhosttyShellIntegration.configure(
            shellPath: shellPath,
            args: profile.shellArguments,
            loginShellName: profile.useLoginShell ? "-\(shellDisplayName)" : nil,
            profile: profile,
            environment: &env
        )
        let envList = env.map { "\($0.key)=\($0.value)" }

        let dir = initialDirectory ?? NSHomeDirectory()
        startDirectoryUsed = dir

        let pty = LocalPTYSession(
            onOutput: { [weak self] data in
                guard let owner = self else { return }
                SecureInputManager.shared.observeTerminalOutput(data, for: owner)
                owner.ghosttySession.receive(data)
            },
            onExit: { [weak self] code, runtimeMs in
                guard let owner = self else { return }
                owner.handleProcessExit(code: code, runtimeMs: runtimeMs)
            }
        )
        ptySession = pty
        pty.start(
            executable: launch.executable,
            args: launch.args,
            environment: envList,
            execName: launch.execName,
            currentDirectory: dir,
            columns: max(40, profile.columns),
            rows: max(10, profile.rows)
        )
        sendInitialCommand(profile.initialCommand, generation: generation)
    }

    private func sendInitialCommand(_ command: String, generation: Int) {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.hasStarted, !self.processExited, self.startupGeneration == generation else { return }
            self.ptySession?.send(Data((command + "\n").utf8))
        }
    }

    func restart() {
        guard hasStarted, processExited else { return }
        processExited = false
        hasStarted = false
        terminalTitle = ""
        osc7Directory = nil
        ghosttySession.receive("\u{1b}c")
        start(initialDirectory: startDirectoryUsed)
        delegate?.sessionTitleDidChange(self)
    }

    func terminate() {
        guard hasStarted, !processExited else { return }
        ptySession?.terminate()
    }

    // MARK: Profile application

    private func reapplyFromStore() {
        let updated = SettingsStore.shared.profile(withID: appliedProfile.id) ?? appliedProfile
        apply(updated, force: true)
    }

    func apply(_ profile: Profile, force: Bool = false) {
        let old = appliedProfile
        appliedProfile = profile
        guard force || profile != old else { return }

        let opacity = effectiveOpacity(for: profile)
        let transparent = opacity < 0.999
        appliedTransparencyFlag = SettingsStore.shared.settings.ui.useTransparency

        terminalController?.setColorScheme(ghosttyColorScheme(for: currentAppearanceVariant()))
        terminalController?.setTerminalConfiguration(ghosttyTerminalConfiguration(for: profile))
        terminalController?.setTheme(ghosttyTheme(for: profile))

        let activeScheme = profile.activeColorScheme
        let schemeBg = NSColor(activeScheme.background)
        layer?.backgroundColor = transparent ? NSColor.clear.cgColor : schemeBg.cgColor
        termView.layer?.backgroundColor = NSColor.clear.cgColor

        needsLayout = true
        termView.fitToSize()
        termView.needsDisplay = true
        window?.invalidateShadow()
    }

    private func ghosttyColorScheme(for appearance: AppearanceVariant) -> TerminalColorScheme {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        }
    }

    private func ghosttyTerminalConfiguration(for profile: Profile) -> TerminalConfiguration {
        TerminalConfiguration(startingFrom: .default) { builder in
            let fontSize = Float(CGFloat(profile.fontSize) + fontDelta)
            if !profile.fontName.isEmpty {
                builder.withFontFamily(profile.fontName)
            }
            builder.withFontSize(fontSize)
            builder.withCursorStyle(ghosttyCursorStyle(for: profile))
            builder.withCursorStyleBlink(profile.cursorBlink)
            builder.withWindowPaddingX(0)
            builder.withWindowPaddingY(0)
            builder.withCustom("copy-on-select", SettingsStore.shared.settings.ui.copyOnSelect ? "clipboard" : "false")
            builder.withCustom("clipboard-read", "allow")
            builder.withCustom("clipboard-write", "allow")
            builder.withCustom("term", profile.termVariable.isEmpty ? "xterm-ghostty" : profile.termVariable)
            builder.withCustom("shell-integration", profile.shellIntegration.ghosttyValue)
            let features = GhosttyShellIntegration.ghosttyConfigFeatures(
                profile.shellIntegrationFeatures,
                cursorBlink: profile.cursorBlink
            )
            if !features.isEmpty {
                builder.withCustom("shell-integration-features", features)
            }
            builder.withCustom("confirm-close-surface", "false")
            builder.withCustom("mouse-reporting", profile.mouseReporting ? "true" : "false")
            builder.withCustom("macos-option-as-alt", profile.optionAsMeta ? "true" : "false")
            builder.withCustom("scrollback-limit", "\(scrollbackLimitBytes(for: profile))")
            builder.withCustom("macos-auto-secure-input", SettingsStore.shared.settings.ui.autoSecureInput ? "true" : "false")
            builder.withCustom("macos-secure-input-indication", SettingsStore.shared.settings.ui.secureInputIndication ? "true" : "false")
            builder.applyGhosttyOverrides(profile.ghosttyConfigOverrides)
        }
    }

    private func ghosttyTheme(for profile: Profile) -> TerminalTheme {
        TerminalTheme(
            light: ghosttyColorConfiguration(for: profile.lightScheme, profile: profile),
            dark: ghosttyColorConfiguration(for: profile.darkScheme, profile: profile)
        )
    }

    private func ghosttyColorConfiguration(for scheme: ColorScheme, profile: Profile) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withBackground(scheme.background.ghosttyHex)
            builder.withForeground(scheme.foreground.ghosttyHex)
            builder.withCursorColor(scheme.cursor.ghosttyHex)
            builder.withCursorText(scheme.cursorText.ghosttyHex)
            builder.withSelectionBackground(scheme.selection.ghosttyHex)
            builder.withSelectionForeground(scheme.foreground.ghosttyHex)
            builder.withBackgroundOpacity(ghosttyBackgroundOpacity(for: profile))
            for (index, color) in scheme.ansi.enumerated() {
                builder.withPalette(index, color: color.ghosttyHex)
            }
        }
    }

    private func ghosttyBackgroundOpacity(for profile: Profile) -> Double {
        // In transparent mode the NSWindow supplies the tinted alpha/blur
        // behind the terminal cells, so keep Ghostty's Metal surface clear.
        effectiveOpacity(for: profile) >= 0.999 ? 1 : 0
    }

    private func scrollbackLimitBytes(for profile: Profile) -> Int {
        if profile.unlimitedScrollback {
            return 512 * 1024 * 1024
        }
        let columns = max(profile.columns, 80)
        let lines = max(profile.scrollbackLines, profile.rows)
        return max(1 * 1024 * 1024, columns * lines * 8)
    }

    private func ghosttyCursorStyle(for profile: Profile) -> TerminalCursorStyle {
        switch profile.cursorShape {
        case .block: return .block
        case .underline: return .underline
        case .bar: return .bar
        }
    }

    private func applySaturation(_ saturation: Double, to view: NSView) {
        guard let layer = view.layer else { return }
        if saturation < 0.999 {
            let filter = CIFilter(name: "CIColorControls")
            filter?.setDefaults()
            filter?.setValue(saturation, forKey: kCIInputSaturationKey)
            layer.filters = filter.map { [$0] }
        } else {
            layer.filters = nil
        }
        for subview in view.subviews {
            applySaturation(saturation, to: subview)
        }
    }

    // MARK: Font zoom

    func adjustFontSize(by delta: CGFloat) {
        fontDelta = min(max(fontDelta + delta, -6), 24)
        apply(appliedProfile, force: true)
    }

    func resetFontSize() {
        fontDelta = 0
        apply(appliedProfile, force: true)
    }

    // MARK: Actions

    func clearBuffer() {
        _ = termView.performBindingAction("clear_screen")
        ptySession?.send(Data([0x0c]))
    }

    func setDesaturated(_ desaturated: Bool, amount: Double) {
        inactiveSaturation = desaturated ? 1 - min(max(amount, 0), 1) : 1
        applySaturation(inactiveSaturation, to: termView)
    }

    func setBroadcasting(_ on: Bool, sink: ((ArraySlice<UInt8>) -> Void)?) {
        termView.broadcastSink = on ? sink : nil
        layer?.borderWidth = on ? 2 : 0
        layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.6).cgColor
    }

    func sendRaw(_ data: ArraySlice<UInt8>) {
        guard hasStarted, !processExited else { return }
        ptySession?.send(data)
    }

    @discardableResult
    func performGhosttyAction(_ action: String) -> Bool {
        termView.performBindingAction(action)
    }

    private func handleBell() {
        if appliedProfile.audibleBell { NSSound.beep() }
        if appliedProfile.visualBell { flash() }
    }

    private func flash() {
        flashView.alphaValue = 0.35
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            flashView.animator().alphaValue = 0
        }
    }

    private func updateSecureInputIndicator() {
        secureInputIndicator.isHidden = !SettingsStore.shared.settings.ui.secureInputIndication
            || !SecureInputManager.shared.isEnabled
    }

    // MARK: Titles & directories

    var isBusy: Bool {
        guard hasStarted, !processExited, let pid = ptySession?.shellPid else { return false }
        return processHasChildren(pid: pid)
    }

    var currentWorkingDirectory: String? {
        if let osc7 = osc7Directory { return osc7 }
        guard hasStarted, !processExited, let pid = ptySession?.shellPid else { return nil }
        return processCurrentDirectory(pid: pid)
    }

    var displayTitle: String {
        if !terminalTitle.isEmpty { return terminalTitle }
        if let dir = currentWorkingDirectory {
            return "\(shellDisplayName) - \(dir.abbreviatingTilde)"
        }
        return shellDisplayName
    }

    var visibleTextSnapshot: String {
        ghosttySession.readViewportText() ?? ""
    }

    var renderedGhosttyColorConfig: String {
        terminalController.renderedConfig
            .split(separator: "\n")
            .filter { line in
                line.hasPrefix("background = ")
                    || line.hasPrefix("foreground = ")
                    || line.hasPrefix("cursor-color = ")
                    || line.hasPrefix("cursor-text = ")
                    || line.hasPrefix("selection-background = ")
                    || line.hasPrefix("selection-foreground = ")
                    || line.hasPrefix("background-opacity = ")
                    || line.hasPrefix("palette = ")
            }
            .joined(separator: "\n")
    }

    // MARK: Ghostty callbacks

    func terminalDidChangeTitle(_ title: String) {
        terminalTitle = title
        delegate?.sessionTitleDidChange(self)
    }

    func terminalDidResize(_ size: TerminalGridMetrics) {
        ptySession?.resize(columns: Int(size.columns), rows: Int(size.rows))
    }

    func terminalDidRingBell() {
        handleBell()
    }

    func terminalDidClose(processAlive: Bool) {
        if !processAlive {
            handleProcessExit(code: 0, runtimeMs: 0)
        }
    }

    func terminalDidChangeWorkingDirectory(_ path: String) {
        if let url = URL(string: path), url.isFileURL {
            osc7Directory = url.path
        } else {
            osc7Directory = path
        }
        delegate?.sessionTitleDidChange(self)
    }

    func terminalDidReportProgress(state: TerminalProgressState, percent: Int?) {
        progressState = state
        progressPercent = percent
        delegate?.sessionTitleDidChange(self)
    }

    func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64) {
        lastCommandExitCode = exitCode
        lastCommandDurationNanos = durationNanos
    }

    func terminalDidRequestDesktopNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? displayTitle : title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "dev.ighostty.notification.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            UNUserNotificationCenter.current().add(request)
        }
    }

    func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind) {
        guard let parsed = URL(string: url) else { return }
        NSWorkspace.shared.open(parsed)
    }

    func terminalDidUpdateHoverLink(_ url: String?) {
        termView.toolTip = url
        if url == nil {
            NSCursor.arrow.set()
        } else {
            NSCursor.pointingHand.set()
        }
    }

    func terminalDidRequestTextSelection(_ request: TerminalTextSelectionRequest) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(request.text, forType: .string)
    }

    private func handleProcessExit(code: Int32?, runtimeMs: UInt64) {
        guard !processExited else { return }
        processExited = true
        if let code {
            ghosttySession.finish(exitCode: UInt32(max(code, 0)), runtimeMilliseconds: runtimeMs)
        }
        delegate?.sessionProcessDidTerminate(self, exitCode: code)
        switch appliedProfile.closeOnExit {
        case .always:
            delegate?.sessionRequestsClose(self)
        case .cleanExit:
            if code == 0 {
                delegate?.sessionRequestsClose(self)
            } else {
                showExitMessage(code)
            }
        case .never:
            showExitMessage(code)
        }
    }

    private func showExitMessage(_ exitCode: Int32?) {
        let code = exitCode.map(String.init) ?? "?"
        ghosttySession.receive("\r\n\u{1b}[3m[Process exited with status \(code) - press Cmd-W to close]\u{1b}[0m\r\n")
    }
}

private extension TermColor {
    var ghosttyHex: String {
        hexString
    }
}
