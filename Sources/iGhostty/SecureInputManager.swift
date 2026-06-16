import AppKit
import Carbon

extension Notification.Name {
    static let iGhosttySecureInputChanged = Notification.Name("iGhostty.secureInputChanged")
}

final class SecureInputManager {
    static let shared = SecureInputManager()

    private var manualEnabled = false
    private var autoEnabled = false
    private var enabledByUs = false
    private var autoDisableWorkItem: DispatchWorkItem?

    private init() {}

    var isEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    var isManualEnabled: Bool {
        manualEnabled
    }

    func setManualEnabled(_ enabled: Bool) {
        manualEnabled = enabled
        apply()
    }

    func toggleManual() {
        setManualEnabled(!manualEnabled)
    }

    func observeTerminalOutput(_ data: Data, for session: TerminalSessionView) {
        guard SettingsStore.shared.settings.ui.autoSecureInput,
              let text = String(data: data, encoding: .utf8) else { return }
        if Self.looksLikePasswordPrompt(text) {
            enableAutoForPasswordPrompt()
        }
    }

    private func enableAutoForPasswordPrompt() {
        autoEnabled = true
        apply()
        autoDisableWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.autoEnabled = false
            self?.apply()
        }
        autoDisableWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    private func apply() {
        let shouldEnable = manualEnabled || autoEnabled
        if shouldEnable, !enabledByUs {
            EnableSecureEventInput()
            enabledByUs = true
        } else if !shouldEnable, enabledByUs {
            DisableSecureEventInput()
            enabledByUs = false
        }
        NotificationCenter.default.post(name: .iGhosttySecureInputChanged, object: self)
    }

    private static func looksLikePasswordPrompt(_ text: String) -> Bool {
        let cleaned = text
            .replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard cleaned.hasSuffix(":") || cleaned.hasSuffix("password") || cleaned.hasSuffix("passphrase") else {
            return false
        }
        return cleaned.contains("password") || cleaned.contains("passphrase")
    }
}
