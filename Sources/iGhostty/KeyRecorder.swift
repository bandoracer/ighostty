import AppKit
import SwiftUI

/// A "click to record" shortcut field, like iTerm2's hotkey recorder.
/// Suspends the live global hotkey while recording so the new combo can be typed.
struct KeyComboRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = { code, mods in
            keyCode = code
            modifiers = mods.rawValue
        }
        button.setDisplay(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
        return button
    }

    func updateNSView(_ view: RecorderButton, context: Context) {
        view.onChange = { code, mods in
            keyCode = code
            modifiers = mods.rawValue
        }
        view.setDisplay(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: modifiers))
    }
}

final class RecorderButton: NSButton {
    var onChange: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    private var monitor: Any?
    private var displayCode: UInt16 = 49
    private var displayMods: NSEvent.ModifierFlags = [.option]
    private(set) var isRecording = false

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        stopMonitoring()
    }

    func setDisplay(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        displayCode = keyCode
        displayMods = modifiers
        if !isRecording { refreshTitle() }
    }

    @objc private func toggleRecording() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        title = "Type shortcut (⎋ cancels)"
        HotkeyManager.shared.setSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handle(event)
            return nil // swallow while recording
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { // Esc
            stop()
            return
        }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !mods.isEmpty || functionKeyCodes.contains(event.keyCode) else {
            NSSound.beep()
            return
        }
        displayCode = event.keyCode
        displayMods = mods
        onChange?(event.keyCode, mods)
        stop()
    }

    private func stop() {
        isRecording = false
        stopMonitoring()
        HotkeyManager.shared.setSuspended(false)
        refreshTitle()
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func refreshTitle() {
        title = keyComboDisplayString(keyCode: displayCode, modifiers: displayMods)
    }
}
