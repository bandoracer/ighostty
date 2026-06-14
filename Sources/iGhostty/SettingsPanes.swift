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
            }

            Section("Terminal Core") {
                LabeledContent("Renderer", value: "Metal via libghostty")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkey window

struct HotkeyPane: View {
    @EnvironmentObject var store: SettingsStore
    @State private var axTrusted = AXIsProcessTrusted()
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
                let trusted = AXIsProcessTrusted()
                if trusted != axTrusted { axTrusted = trusted }
            }

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
                Toggle("Start at login (background, no windows)", isOn: loginItemBinding)
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
        .onAppear { loginItemStatus = Self.loginAgent.status }
    }

    static let loginAgent = SMAppService.agent(plistName: "dev.ighostty.background.plist")
    @State private var loginItemStatus: SMAppService.Status = SMAppService.agent(plistName: "dev.ighostty.background.plist").status
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
                    if enable {
                        try Self.loginAgent.register()
                    } else {
                        try Self.loginAgent.unregister()
                    }
                    loginItemError = nil
                } catch {
                    loginItemError = error.localizedDescription
                }
                loginItemStatus = Self.loginAgent.status
            }
        )
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
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Core", value: "GhosttyTerminal / libghostty — Metal renderer")
                LabeledContent("Emulation", value: "xterm-256color, truecolor, mouse, hyperlinks, Kitty graphics")
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
