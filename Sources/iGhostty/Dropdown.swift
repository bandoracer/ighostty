import AppKit
import Carbon.HIToolbox

// MARK: - Global hotkey (Carbon — works without accessibility permissions)

final class HotkeyManager {
    static let shared = HotkeyManager()

    var handler: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var lastRegistration: (keyCode: UInt32, modifiers: UInt32)?
    private var suspended = false

    func updateRegistration(enabled: Bool, keyCode: UInt32, carbonModifiers: UInt32) {
        unregister()
        guard enabled else {
            lastRegistration = nil
            return
        }
        lastRegistration = (keyCode, carbonModifiers)
        guard !suspended else { return }
        register(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }

    /// Temporarily release the hotkey (used while recording a new shortcut).
    func setSuspended(_ flag: Bool) {
        suspended = flag
        if flag {
            unregister()
        } else if let last = lastRegistration {
            register(keyCode: last.keyCode, carbonModifiers: last.modifiers)
        }
    }

    private func register(keyCode: UInt32, carbonModifiers: UInt32) {
        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x54524D33) /* 'TRM3' */, id: 1)
        RegisterEventHotKey(keyCode, carbonModifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.handler?() }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }
}

// MARK: - Double-tap modifier hotkey (iTerm2-style)

/// Detects a quick double-tap of a lone modifier key (default: Control).
/// Uses NSEvent flagsChanged monitors: the local monitor always works; the
/// global monitor (other apps focused) requires Accessibility access.
final class ModifierTapDetector {
    static let shared = ModifierTapDetector()
    static let tapInterval: TimeInterval = 0.35

    var handler: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var targetFlag: NSEvent.ModifierFlags = .control
    private var modifierIsDown = false
    private var lastTapDownTime: TimeInterval = 0

    func start(modifier: NSEvent.ModifierFlags) {
        stop()
        targetFlag = modifier
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.process(flags: event.modifierFlags, timestamp: event.timestamp)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.process(flags: event.modifierFlags, timestamp: event.timestamp)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        modifierIsDown = false
        lastTapDownTime = 0
    }

    func process(flags rawFlags: NSEvent.ModifierFlags, timestamp: TimeInterval) {
        let flags = rawFlags.intersection([.command, .option, .control, .shift])

        if flags == targetFlag, !modifierIsDown {
            // Clean press of exactly the target modifier.
            modifierIsDown = true
            if lastTapDownTime > 0, timestamp - lastTapDownTime < Self.tapInterval {
                lastTapDownTime = 0
                DispatchQueue.main.async { [weak self] in self?.handler?() }
            } else {
                lastTapDownTime = timestamp
            }
        } else if flags.contains(targetFlag), flags != targetFlag {
            // Target held together with other modifiers — not a tap.
            modifierIsDown = true
            lastTapDownTime = 0
        } else if !flags.contains(targetFlag), modifierIsDown {
            modifierIsDown = false
            // A slow press-and-release isn't a tap candidate.
            if timestamp - lastTapDownTime >= Self.tapInterval {
                lastTapDownTime = 0
            }
        }
    }

    /// Test hook: replay a synthetic down/up/down tap sequence through the
    /// detection logic.
    func simulateDoubleTap() {
        let t = ProcessInfo.processInfo.systemUptime
        process(flags: targetFlag, timestamp: t)
        process(flags: [], timestamp: t + 0.06)
        process(flags: targetFlag, timestamp: t + 0.18)
        process(flags: [], timestamp: t + 0.24)
    }
}

// MARK: - Drop-down terminal window

private final class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DropdownSurfaceView: NSView {
    private let maskLayer = CAShapeLayer()
    private let outlineLayer = CAShapeLayer()
    private var backingScale: CGFloat = 1

    var fillColor: NSColor = .windowBackgroundColor {
        didSet { layer?.backgroundColor = fillColor.cgColor }
    }

    var outlineColor: NSColor = .separatorColor {
        didSet { outlineLayer.strokeColor = outlineColor.cgColor }
    }

    var cornerRadius: CGFloat = 16 {
        didSet { updateShape() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func makeBackingLayer() -> CALayer {
        CALayer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureScale(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
    }

    override func layout() {
        super.layout()
        updateShape()
    }

    func configure(fillColor: NSColor, outlineColor: NSColor, cornerRadius: CGFloat, scale: CGFloat) {
        self.fillColor = fillColor
        self.outlineColor = outlineColor
        self.cornerRadius = cornerRadius
        configureScale(scale)
    }

    private func setupLayer() {
        guard let layer else { return }
        layer.backgroundColor = fillColor.cgColor
        layer.mask = maskLayer
        layer.addSublayer(outlineLayer)

        maskLayer.fillColor = NSColor.black.cgColor
        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = outlineColor.cgColor
        outlineLayer.lineJoin = .round
        outlineLayer.lineCap = .round
        outlineLayer.zPosition = 1
    }

    private func configureScale(_ scale: CGFloat) {
        backingScale = max(scale, 1)
        layer?.contentsScale = backingScale
        maskLayer.contentsScale = backingScale
        outlineLayer.contentsScale = backingScale
        outlineLayer.lineWidth = 1 / backingScale
        updateShape()
    }

    private func updateShape() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let radius = min(cornerRadius, bounds.width / 2, bounds.height / 2)
        let fullPath = Self.bottomRoundedPath(in: bounds, radius: radius)
        let inset = outlineLayer.lineWidth / 2
        let outlineBounds = bounds.insetBy(dx: inset, dy: inset)
        let outlinePath = Self.bottomOutlinePath(
            in: outlineBounds,
            radius: max(0, radius - inset)
        )

        maskLayer.frame = bounds
        maskLayer.path = fullPath
        outlineLayer.frame = bounds
        outlineLayer.path = outlinePath
    }

    private static func bottomRoundedPath(in bounds: CGRect, radius: CGFloat) -> CGPath {
        let rect = bounds.standardized
        let radius = max(0, min(radius, rect.width / 2, rect.height / 2))
        let path = CGMutablePath()

        guard radius > 0 else {
            path.addRect(rect)
            return path
        }

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX - radius, y: rect.minY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX, y: rect.minY + radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private static func bottomOutlinePath(in bounds: CGRect, radius: CGFloat) -> CGPath {
        let rect = bounds.standardized
        let radius = max(0, min(radius, rect.width / 2, rect.height / 2))
        let path = CGMutablePath()

        guard radius > 0 else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return path
        }

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius),
            radius: radius
        )
        return path
    }
}

struct DropdownDisplayGeometry {
    let screenFrame: NSRect
    let safeAreaInsets: NSEdgeInsets
    let auxiliaryTopAreas: [NSRect]

    init(screen: NSScreen) {
        self.init(
            screenFrame: screen.frame,
            safeAreaInsets: screen.safeAreaInsets,
            auxiliaryTopAreas: [screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea].compactMap { $0 }
        )
    }

    init(
        screenFrame: NSRect,
        safeAreaInsets: NSEdgeInsets = NSEdgeInsetsZero,
        auxiliaryTopAreas: [NSRect] = []
    ) {
        self.screenFrame = screenFrame
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopAreas = auxiliaryTopAreas
    }

    var availableFrame: NSRect {
        screenFrame
    }

    var contentInsets: NSEdgeInsets {
        NSEdgeInsets(top: topUnsafeInset, left: 0, bottom: 0, right: 0)
    }

    private var topUnsafeInset: CGFloat {
        max(0, safeAreaInsets.top, auxiliaryTopInset)
    }

    private var auxiliaryTopInset: CGFloat {
        guard let lowestAuxiliaryTopY = auxiliaryTopAreas.map(\.minY).min() else {
            return 0
        }
        return max(0, screenFrame.maxY - lowestAuxiliaryTopY)
    }
}

/// Guake/iTerm2-style hotkey window: slides down from the top of the screen,
/// joins every Space, keeps its sessions alive while hidden, auto-hides on
/// focus loss unless pinned.
final class DropdownWindowController: NSObject, NSWindowDelegate {
    static let shared = DropdownWindowController()

    private var panel: DropdownPanel?
    private(set) var tabVC: TerminalTabViewController?
    private var pinButton: NSButton?
    private var hiding = false

    var pinned = false {
        didSet { updatePinButton() }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = ensurePanel()
        let hk = SettingsStore.shared.settings.hotkey
        let layout = targetLayout()
        let final = layout.frame
        let start = final.offsetBy(dx: 0, dy: min(48, final.height * 0.12))

        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        applyContentInsets(layout.contentInsets)
        applyAppearance(to: panel)
        tabVC?.focusActiveSession()

        let duration = max(0.01, hk.animationDuration)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(final, display: true)
            panel.animator().alphaValue = 1
        }
        // Settle the end state ourselves — completion delivery isn't relied on.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak panel] in
            guard let panel, panel.isVisible else { return }
            panel.alphaValue = 1
            panel.setFrame(final, display: true)
            NSLog("iGhostty dropdown shown: target=%@ actual=%@", NSStringFromRect(final), NSStringFromRect(panel.frame))
        }
    }

    func hide() {
        guard let panel, panel.isVisible, !hiding else { return }
        hiding = true
        let duration = max(0.01, SettingsStore.shared.settings.hotkey.animationDuration)
        let up = panel.frame.offsetBy(dx: 0, dy: min(48, panel.frame.height * 0.12))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(up, display: true)
            panel.animator().alphaValue = 0
        }
        // Settle the end state ourselves — completion delivery isn't relied on.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            panel.orderOut(nil)
            panel.alphaValue = 0
            self?.hiding = false
            // Hand focus back unless another iGhostty window is open. (deactivate,
            // not hide — hidden apps get notification delivery deferred, which
            // would stall the background hotkey service.)
            let othersVisible = NSApp.windows.contains {
                $0 !== panel && $0.isVisible && !($0 is NSPanel) && $0.contentViewController != nil
            }
            if !othersVisible {
                NSApp.deactivate()
            }
        }
    }

    /// Reframe (and restyle) live when settings change.
    func settingsDidChange() {
        guard let panel, panel.isVisible, !hiding else { return }
        let layout = targetLayout()
        panel.setFrame(layout.frame, display: true, animate: true)
        applyContentInsets(layout.contentInsets)
        applyAppearance(to: panel)
    }

    private func dropdownProfile() -> Profile {
        let store = SettingsStore.shared
        let hk = store.settings.hotkey
        return store.profile(withID: hk.profileID) ?? store.defaultProfile
    }

    private var appliedBlurRadius = 0

    private func applyAppearance(to panel: NSWindow) {
        let profile = dropdownProfile()
        let opacity = effectiveOpacity(for: profile)
        let scheme = profile.activeColorScheme
        panel.isOpaque = false
        panel.backgroundColor = .clear
        if let surface = tabVC?.view as? DropdownSurfaceView {
            surface.configure(
                fillColor: NSColor(scheme.background).withAlphaComponent(opacity),
                outlineColor: NSColor.white.withAlphaComponent(0.28),
                cornerRadius: preferredWindowCornerRadius(),
                scale: panel.backingScaleFactor
            )
        } else {
            tabVC?.view.layer?.backgroundColor = NSColor(scheme.background).withAlphaComponent(opacity).cgColor
        }
        applyBlur(to: panel)
    }

    private func applyContentInsets(_ insets: NSEdgeInsets) {
        tabVC?.view.additionalSafeAreaInsets = insets
        updatePinButtonFrame(topInset: insets.top)
        tabVC?.view.needsLayout = true
    }

    private func applyBlur(to panel: NSWindow) {
        let radius = effectiveBlurRadius(for: dropdownProfile())
        guard radius > 0 || appliedBlurRadius > 0 else { return }
        WindowBlur.apply(to: panel, radius: radius)
        appliedBlurRadius = radius
    }

    // MARK: Internals

    private struct DropdownLayout {
        let frame: NSRect
        let contentInsets: NSEdgeInsets
    }

    private func targetLayout() -> DropdownLayout {
        let hk = SettingsStore.shared.settings.hotkey
        let screen = currentScreen()
        // Keep the classic top-of-screen hotkey-window placement. On notched
        // displays, only the terminal content is inset below the unsafe strip.
        let geometry = DropdownDisplayGeometry(screen: screen)
        let sf = geometry.availableFrame
        let profile = dropdownProfile()
        let font = resolvedFont(name: profile.fontName, size: CGFloat(profile.fontSize))
        let cell = terminalCellSize(font: font)
        let rows = CGFloat(min(max(hk.rows, 5), 150))
        let requestedHeight = rows * cell.height + CGFloat(profile.padding) * 2
        let width = sf.width * min(max(hk.widthFraction, 0.2), 1.0)
        let height = min(max(requestedHeight, cell.height * 5), sf.height * 0.95)
        let frame = backingAligned(
            NSRect(x: sf.midX - width / 2, y: sf.maxY - height, width: width, height: height),
            for: screen
        )
        return DropdownLayout(
            frame: frame,
            contentInsets: geometry.contentInsets
        )
    }

    private func backingAligned(_ rect: NSRect, for screen: NSScreen) -> NSRect {
        let scale = max(screen.backingScaleFactor, 1)
        func align(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded() / scale
        }

        let minX = align(rect.minX)
        let maxX = align(rect.maxX)
        let minY = align(rect.minY)
        let maxY = align(rect.maxY)
        return NSRect(
            x: minX,
            y: minY,
            width: max(1 / scale, maxX - minX),
            height: max(1 / scale, maxY - minY)
        )
    }

    private func currentScreen() -> NSScreen {
        let hk = SettingsStore.shared.settings.hotkey
        if hk.followMouseScreen {
            let mouse = NSEvent.mouseLocation
            if let s = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
                return s
            }
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func ensurePanel() -> DropdownPanel {
        if let panel { return panel }

        let store = SettingsStore.shared
        let hk = store.settings.hotkey
        let profile = store.profile(withID: hk.profileID) ?? store.defaultProfile

        let vc = TerminalTabViewController(profile: profile, initialDirectory: nil) {
            DropdownSurfaceView(frame: NSRect(x: 0, y: 0, width: 900, height: 480))
        }
        vc.onLastPaneClosed = { [weak self] in self?.teardown() }

        let panel = DropdownPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 480),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.tabbingMode = .disallowed
        panel.delegate = self
        panel.contentViewController = vc

        if let surface = vc.view as? DropdownSurfaceView {
            surface.configure(
                fillColor: NSColor(profile.activeColorScheme.background)
                    .withAlphaComponent(effectiveOpacity(for: profile)),
                outlineColor: NSColor.white.withAlphaComponent(0.28),
                cornerRadius: preferredWindowCornerRadius(),
                scale: panel.backingScaleFactor
            )
        }

        let pin = NSButton(
            image: NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin drop-down terminal") ?? NSImage(),
            target: self,
            action: #selector(togglePin)
        )
        pin.isBordered = false
        pin.bezelStyle = .regularSquare
        pin.frame = pinButtonFrame(topInset: 0)
        pin.autoresizingMask = [.minXMargin, .minYMargin]
        pin.toolTip = "Keep open when iGhostty loses focus"
        vc.view.addSubview(pin)
        pinButton = pin

        self.panel = panel
        self.tabVC = vc
        updatePinButton()
        return panel
    }

    private func teardown() {
        tabVC?.terminateAll()
        panel?.orderOut(nil)
        panel = nil
        tabVC = nil
        pinButton = nil
        pinned = false
    }

    @objc private func togglePin() {
        pinned.toggle()
    }

    private func updatePinButton() {
        let name = pinned ? "pin.fill" : "pin"
        pinButton?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Pin drop-down terminal")
        pinButton?.contentTintColor = pinned ? .controlAccentColor : .tertiaryLabelColor
    }

    private func updatePinButtonFrame(topInset: CGFloat) {
        pinButton?.frame = pinButtonFrame(topInset: topInset)
    }

    private func pinButtonFrame(topInset: CGFloat) -> NSRect {
        guard let view = tabVC?.view else {
            return NSRect(x: 770, y: 472, width: 24, height: 22)
        }
        return NSRect(
            x: view.bounds.maxX - 30,
            y: view.bounds.maxY - 28 - max(0, topInset),
            width: 24,
            height: 22
        )
    }

    func terminateAll() {
        tabVC?.terminateAll()
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard SettingsStore.shared.settings.hotkey.autoHide, !pinned else { return }
        hide()
    }
}
