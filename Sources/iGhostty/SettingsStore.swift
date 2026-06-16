import Foundation
import Combine

extension Notification.Name {
    static let iGhosttySettingsChanged = Notification.Name("iGhostty.settingsChanged")
    /// Posted with a profile UUID to ask the Profiles pane to select it (⌘I).
    static let iGhosttySelectProfile = Notification.Name("iGhostty.selectProfile")
}

/// Single source of truth for all settings. Persists to a JSON file in
/// Application Support and broadcasts changes so open terminals update live.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            scheduleSave()
            NotificationCenter.default.post(name: .iGhosttySettingsChanged, object: nil)
        }
    }

    let directoryURL: URL
    let fileURL: URL
    private var pendingSave: DispatchWorkItem?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directoryURL = appSupport.appendingPathComponent("iGhostty", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("settings.json")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: fileURL) {
            if var decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                let migrated = decoded.migrateLegacyDefaults()
                settings = decoded
                if migrated { saveNow() }
            } else {
                // Never destroy a file we can't read — move it aside and start fresh.
                let backup = directoryURL.appendingPathComponent("settings.unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: fileURL, to: backup)
                settings = .freshDefault()
                saveNow()
            }
        } else {
            settings = .freshDefault()
            saveNow()
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func profile(withID id: UUID?) -> Profile? {
        guard let id else { return nil }
        return settings.profiles.first { $0.id == id }
    }

    var defaultProfile: Profile {
        profile(withID: settings.defaultProfileID) ?? settings.profiles.first ?? .placeholder
    }

    func exportSettings(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }

    func importSettings(from url: URL) throws {
        let data = try Data(contentsOf: url)
        var decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        decoded.migrateLegacyDefaults()
        settings = decoded
    }
}

// MARK: - Color scheme status

extension SettingsStore {
    /// The user-created scheme with this name, if any.
    func customScheme(named name: String) -> ColorScheme? {
        settings.customSchemes.first { $0.name == name }
    }

    /// Whether a scheme is user-created (saved in customSchemes or flagged `.user`).
    func isUserCreatedScheme(_ scheme: ColorScheme) -> Bool {
        scheme.origin == .user || customScheme(named: scheme.name) != nil
    }

    /// The pristine scheme this one is based on (a saved user scheme or a built-in),
    /// used to detect unsaved edits. Returns nil when there is nothing to compare to.
    func canonicalScheme(for scheme: ColorScheme, appearance: AppearanceVariant) -> ColorScheme? {
        if let custom = customScheme(named: scheme.name) {
            return custom.withOrigin(.user)
        }
        guard scheme.origin != .user else { return nil }

        let builtIns = ColorScheme.builtIns(for: appearance)
        if let builtIn = builtIns.first(where: { $0.name == scheme.name }) {
            return builtIn
        }
        if let baseName = scheme.legacyCustomBaseName,
           let builtIn = builtIns.first(where: { $0.name == baseName }) {
            return builtIn
        }
        return nil
    }

    /// Whether a scheme's colors diverge from its canonical source.
    func isModifiedScheme(_ scheme: ColorScheme, for appearance: AppearanceVariant) -> Bool {
        guard let canonical = canonicalScheme(for: scheme, appearance: appearance) else { return false }
        return !scheme.hasSameColors(as: canonical)
    }
}
