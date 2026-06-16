import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - General

struct GeneralPane: View {
    @EnvironmentObject var store: SettingsStore

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $store.settings.ui.theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                Picker("Window style", selection: $store.settings.ui.windowStyle) {
                    ForEach(WindowStyle.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Desaturate inactive split panes", isOn: $store.settings.ui.desaturateInactivePanes)
                if store.settings.ui.desaturateInactivePanes {
                    LabeledContent("Desaturation") {
                        HStack {
                            Slider(value: $store.settings.ui.desaturationAmount, in: 0...1.0)
                            Text("\(Int(store.settings.ui.desaturationAmount * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }

            Section("Behavior") {
                Picker("Default profile", selection: $store.settings.defaultProfileID) {
                    ForEach(store.settings.profiles) { Text($0.name).tag($0.id) }
                }
                Toggle("Copy to clipboard on select", isOn: $store.settings.ui.copyOnSelect)
                Toggle("Confirm closing running sessions", isOn: $store.settings.ui.confirmQuit)
                Toggle("Automatically use Secure Keyboard Entry at password prompts", isOn: $store.settings.ui.autoSecureInput)
                Toggle("Show Secure Keyboard Entry indicator", isOn: $store.settings.ui.secureInputIndication)
                Picker("Shortcuts automation", selection: $store.settings.ui.automationPermission) {
                    ForEach(AutomationPermission.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Terminal Core") {
                LabeledContent("Renderer", value: "Metal via libghostty")
                LabeledContent("Ghostty resources") {
                    if let issue = GhosttyResources.validationIssue {
                        Text(issue)
                            .foregroundStyle(.red)
                    } else {
                        Text(GhosttyResources.resourcesDir?.path.abbreviatingTilde ?? "Bundled")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkey window

struct HotkeyPane: View {
    @EnvironmentObject var store: SettingsStore
    @State private var axTrusted = AccessibilityPermission.isGranted
    private let axCheck = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Show a drop-down terminal with a global hotkey", isOn: $store.settings.hotkey.enabled)
                Picker("Activate with", selection: $store.settings.hotkey.activationMode) {
                    ForEach(HotkeyActivationMode.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!store.settings.hotkey.enabled)

                if store.settings.hotkey.activationMode == .doubleTapModifier {
                    Picker("Modifier", selection: $store.settings.hotkey.doubleTapModifier) {
                        Text("⌃ Control").tag(NSEvent.ModifierFlags.control.rawValue)
                        Text("⌥ Option").tag(NSEvent.ModifierFlags.option.rawValue)
                        Text("⌘ Command").tag(NSEvent.ModifierFlags.command.rawValue)
                        Text("⇧ Shift").tag(NSEvent.ModifierFlags.shift.rawValue)
                    }
                    .disabled(!store.settings.hotkey.enabled)
                    LabeledContent("Accessibility") {
                        if axTrusted {
                            Label("Granted — double-tap works system-wide", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            HStack {
                                Label("Needed for system-wide detection", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Button("Grant…") { requestAccessibility() }
                            }
                        }
                    }
                } else {
                    LabeledContent("Hotkey") {
                        KeyComboRecorder(
                            keyCode: $store.settings.hotkey.keyCode,
                            modifiers: $store.settings.hotkey.modifierFlags
                        )
                        .frame(width: 200, height: 24)
                    }
                    .disabled(!store.settings.hotkey.enabled)
                }

                Picker("Profile", selection: $store.settings.hotkey.profileID) {
                    Text("Default profile").tag(UUID?.none)
                    ForEach(store.settings.profiles) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .disabled(!store.settings.hotkey.enabled)
            } footer: {
                Text(store.settings.hotkey.activationMode == .doubleTapModifier
                     ? "Quickly tap the modifier twice. Works inside iGhostty immediately; detecting it while other apps are focused requires Accessibility access (like iTerm2). The panel covers the menu bar, joins every Space, and keeps its sessions running while hidden."
                     : "The shortcut works system-wide with no permissions. The panel covers the menu bar, joins every Space, and keeps its sessions running while hidden.")
                    .foregroundStyle(.secondary)
            }
            .onReceive(axCheck) { _ in
                refreshAccessibilityState()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refreshAccessibilityState()
            }
            .onAppear { refreshAccessibilityState() }

            Section("Window") {
                LabeledContent("Height") {
                    HStack {
                        TextField("", value: hotkeyRows, format: .number)
                            .frame(width: 56)
                        Stepper("", value: hotkeyRows, in: 5...150)
                        Text("rows")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!store.settings.hotkey.enabled)
                fractionSlider("Width", value: $store.settings.hotkey.widthFraction, range: 0.3...1.0)
                LabeledContent("Animation") {
                    HStack {
                        Slider(value: $store.settings.hotkey.animationDuration, in: 0...0.4)
                        Text("\(Int(store.settings.hotkey.animationDuration * 1000)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                    }
                }
                Toggle("Hide when iGhostty loses focus", isOn: $store.settings.hotkey.autoHide)
                Toggle("Open on the screen with the mouse pointer", isOn: $store.settings.hotkey.followMouseScreen)
            }

            Section("Background") {
                Toggle("⌘Q keeps iGhostty running in the background", isOn: $store.settings.hotkey.keepAvailableInBackground)
                Toggle("Show notice when Dock Quit keeps iGhostty running", isOn: $store.settings.ui.showDockQuitBackgroundNotice)
                    .disabled(!store.settings.hotkey.enabled || !store.settings.hotkey.keepAvailableInBackground)
                Toggle("Start at login (background, no windows)", isOn: loginItemBinding)
                    .disabled(LoginItemService.availabilityIssue != nil)
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if loginItemStatus == .requiresApproval {
                    Text("Approve iGhostty in System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button("Test Drop-down Terminal") {
                    DropdownWindowController.shared.toggle()
                }
            } footer: {
                Text("With both background options on, the drop-down is always one double-tap away: iGhostty starts invisibly at login, and ⌘Q only closes terminal windows (drop-down sessions survive). Quit completely with ⌥⌘Q. Tip: the pin button in the drop-down's top-right corner keeps it open while you work elsewhere.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshLoginItemStatus()
            loginItemError = LoginItemService.availabilityIssue
        }
    }

    @State private var loginItemStatus: SMAppService.Status = LoginItemService.status
    @State private var loginItemError: String?

    private var hotkeyRows: Binding<Int> {
        Binding(
            get: { store.settings.hotkey.rows },
            set: { store.settings.hotkey.rows = min(max($0, 5), 150) }
        )
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { loginItemStatus == .enabled },
            set: { enable in
                do {
                    try LoginItemService.setEnabled(enable)
                    loginItemError = LoginItemService.availabilityIssue
                } catch {
                    loginItemError = error.localizedDescription
                }
                refreshLoginItemStatus()
            }
        )
    }

    private func refreshLoginItemStatus() {
        loginItemStatus = LoginItemService.status
    }

    private func fractionSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(label) {
            HStack {
                Slider(value: value, in: range)
                Text("\(Int(value.wrappedValue * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .disabled(!store.settings.hotkey.enabled)
    }

    private func requestAccessibility() {
        _ = AccessibilityPermission.request()
        AccessibilityPermission.openSettings()
        refreshAccessibilityState()
    }

    private func refreshAccessibilityState() {
        let trusted = AccessibilityPermission.isGranted
        if trusted != axTrusted { axTrusted = trusted }
    }
}

// MARK: - Advanced

struct AdvancedPane: View {
    @EnvironmentObject var store: SettingsStore
    @State private var confirmingReset = false
    @State private var importError: String?

    var body: some View {
        Form {
            Section("Settings File") {
                LabeledContent("Location", value: store.fileURL.path.abbreviatingTilde)
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                    Button("Export…") { exportSettings() }
                    Button("Import…") { importSettings() }
                }
            }

            Section("Maintenance") {
                Button("Restore Built-in Profiles") {
                    let existing = Set(store.settings.profiles.map(\.name))
                    for profile in AppSettings.freshDefault().profiles where !existing.contains(profile.name) {
                        store.settings.profiles.append(profile)
                    }
                }
                Button("Reset All Settings…", role: .destructive) {
                    confirmingReset = true
                }
                .confirmationDialog(
                    "Reset all settings to defaults? Profiles and imported schemes will be removed.",
                    isPresented: $confirmingReset
                ) {
                    Button("Reset Everything", role: .destructive) {
                        store.settings = .freshDefault()
                    }
                }
            }

            Section("Updates") {
                UpdateSettingsView()
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Core", value: "GhosttyTerminal / libghostty — Metal renderer")
                LabeledContent("Emulation", value: "xterm-ghostty, truecolor, mouse, hyperlinks, Kitty graphics")
            }
        }
        .formStyle(.grouped)
        .alert("Import failed", isPresented: .init(get: { importError != nil }, set: { _ in importError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "iGhostty Settings.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportSettings(to: url)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.importSettings(from: url)
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

private struct UpdateSettingsView: View {
    @State private var automaticallyChecks = false
    @State private var automaticallyDownloads = false
    @State private var canCheck = false
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Toggle("Check for updates automatically", isOn: Binding(
            get: { automaticallyChecks },
            set: { value in
                AppUpdater.shared.automaticallyChecksForUpdates = value
                syncFromUpdater()
            }
        ))
        Toggle("Download updates automatically", isOn: Binding(
            get: { automaticallyDownloads },
            set: { value in
                AppUpdater.shared.automaticallyDownloadsUpdates = value
                syncFromUpdater()
            }
        ))
        .disabled(!AppUpdater.shared.allowsAutomaticUpdates)

        HStack {
            Button("Check Now…") {
                AppUpdater.shared.checkForUpdates(nil)
                syncFromUpdater()
            }
            .disabled(!canCheck)
            if let feed = AppUpdater.shared.feedURL?.absoluteString {
                Text(feed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .onAppear { syncFromUpdater() }
        .onReceive(refresh) { _ in syncFromUpdater() }
    }

    private func syncFromUpdater() {
        automaticallyChecks = AppUpdater.shared.automaticallyChecksForUpdates
        automaticallyDownloads = AppUpdater.shared.automaticallyDownloadsUpdates
        canCheck = AppUpdater.shared.canCheckForUpdates
    }
}
