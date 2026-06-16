import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let ansiColorNames = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]

/// A focused editor for one appearance's color scheme: a live preview, the
/// foreground/background/cursor/selection swatches, the 16 ANSI colors, and
/// scheme management (revert, duplicate, rename, delete, import). It is opened
/// from the Colors tab for a specific light or dark slot, so it needs no
/// appearance selector — that distinction lives on the page.
struct ColorSchemeEditor: View {
    @Binding var profile: Profile
    let appearance: AppearanceVariant

    @EnvironmentObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var schemeError: String?

    private var scheme: ColorScheme { profile.colorScheme(for: appearance) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section {
                    SchemePreview(scheme: scheme, fontName: profile.fontName, fontSize: profile.fontSize)
                }
                Section("Text & Cursor") {
                    colorRow("Foreground", \.foreground)
                    colorRow("Background", \.background)
                    colorRow("Cursor", \.cursor)
                    colorRow("Cursor text", \.cursorText)
                    colorRow("Selection", \.selection)
                }
                Section("ANSI Colors") {
                    ansiGrid(range: 0..<8, title: "Normal")
                    ansiGrid(range: 8..<16, title: "Bright")
                }
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: 480, height: 660)
        .alert("Scheme action failed", isPresented: .init(get: { schemeError != nil }, set: { _ in schemeError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(schemeError ?? "")
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit \(appearance.label) Theme")
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(scheme.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if store.isUserCreatedScheme(scheme) { badge("Custom") }
                    if store.isModifiedScheme(scheme, for: appearance) { badge("Modified") }
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            HStack(spacing: 16) {
                actionButton("arrow.uturn.backward", help: "Revert to the original colors",
                             enabled: store.isModifiedScheme(scheme, for: appearance), action: revert)
                actionButton("plus.square.on.square", help: "Duplicate as a new theme",
                             enabled: true, action: duplicate)
                actionButton("pencil", help: "Rename this theme",
                             enabled: store.isUserCreatedScheme(scheme), action: rename)
                actionButton("trash", help: "Delete this theme",
                             enabled: store.isUserCreatedScheme(scheme), role: .destructive, action: delete)
                actionButton("square.and.arrow.down", help: "Import an iTerm2 .itermcolors scheme",
                             enabled: true, action: importScheme)
            }
            .buttonStyle(.borderless)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private func actionButton(
        _ symbol: String,
        help: String,
        enabled: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
        }
        .help(help)
        .disabled(!enabled)
    }

    // MARK: Color editing

    private func colorRow(_ label: String, _ keyPath: WritableKeyPath<ColorScheme, TermColor>) -> some View {
        ColorPicker(label, selection: colorBinding(keyPath), supportsOpacity: false)
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ColorScheme, TermColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(scheme[keyPath: keyPath])) },
            set: { newValue in mutate { $0[keyPath: keyPath] = NSColor(newValue).termColor } }
        )
    }

    private func ansiBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(scheme.ansi[index])) },
            set: { newValue in mutate { $0.ansi[index] = NSColor(newValue).termColor } }
        )
    }

    private func ansiGrid(range: Range<Int>, title: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                ForEach(range, id: \.self) { i in
                    ColorPicker("", selection: ansiBinding(i), supportsOpacity: false)
                        .labelsHidden()
                        .help(i < 8 ? ansiColorNames[i] : "Bright \(ansiColorNames[i - 8])")
                }
            }
        }
    }

    private func mutate(_ change: (inout ColorScheme) -> Void) {
        var updated = scheme
        change(&updated)
        setScheme(updated)
    }

    private func setScheme(_ updated: ColorScheme) {
        switch appearance {
        case .light: profile.lightScheme = updated
        case .dark: profile.darkScheme = updated
        }
        profile.syncLegacyColorScheme()
    }

    // MARK: Management

    private func existingSchemeNames(excluding excluded: String? = nil) -> Set<String> {
        var names = Set(
            ColorScheme.builtIns(for: .light).map(\.name)
                + ColorScheme.builtIns(for: .dark).map(\.name)
                + store.settings.customSchemes.map(\.name)
        )
        if let excluded { names.remove(excluded) }
        return names
    }

    private func customSchemeIndex(named name: String) -> Int? {
        store.settings.customSchemes.firstIndex { $0.name == name }
    }

    private func revert() {
        guard let canonical = store.canonicalScheme(for: scheme, appearance: appearance) else { return }
        setScheme(canonical)
    }

    private func duplicate() {
        var duplicate = scheme
        duplicate.origin = .user
        let baseName = duplicate.legacyCustomBaseName ?? duplicate.name
        duplicate.name = ColorScheme.uniqueName("\(baseName) Copy", avoiding: existingSchemeNames())
        store.settings.customSchemes.append(duplicate)
        setScheme(duplicate)
    }

    private func rename() {
        guard store.isUserCreatedScheme(scheme) else { return }

        let alert = NSAlert()
        alert.messageText = "Rename Color Scheme"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: scheme.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        applyRename(to: field.stringValue)
    }

    private func applyRename(to proposedName: String) {
        let newName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            schemeError = "Color scheme names cannot be empty."
            return
        }
        let oldName = scheme.name
        guard !existingSchemeNames(excluding: oldName).contains(newName) else {
            schemeError = "A color scheme named “\(newName)” already exists."
            return
        }

        if let index = customSchemeIndex(named: oldName) {
            store.settings.customSchemes[index].name = newName
            store.settings.customSchemes[index].origin = .user
            renameReferences(from: oldName, to: newName)
        } else {
            var renamed = scheme
            renamed.name = newName
            renamed.origin = .user
            setScheme(renamed)
        }
    }

    private func renameReferences(from oldName: String, to newName: String) {
        for index in store.settings.profiles.indices {
            if store.settings.profiles[index].lightScheme.name == oldName {
                store.settings.profiles[index].lightScheme.name = newName
                store.settings.profiles[index].lightScheme.origin = .user
            }
            if store.settings.profiles[index].darkScheme.name == oldName {
                store.settings.profiles[index].darkScheme.name = newName
                store.settings.profiles[index].darkScheme.origin = .user
            }
            store.settings.profiles[index].syncLegacyColorScheme()
        }
    }

    private func delete() {
        guard store.isUserCreatedScheme(scheme) else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Color Scheme?"
        alert.informativeText = "Profiles using “\(scheme.name)” will switch back to the default scheme for each appearance."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = scheme.name
        if let index = customSchemeIndex(named: name) {
            store.settings.customSchemes.remove(at: index)
        }
        resetReferences(named: name)
        dismiss()
    }

    private func resetReferences(named name: String) {
        for index in store.settings.profiles.indices {
            if store.settings.profiles[index].lightScheme.name == name {
                store.settings.profiles[index].lightScheme = ColorScheme.defaultLight
            }
            if store.settings.profiles[index].darkScheme.name == name {
                store.settings.profiles[index].darkScheme = ColorScheme.defaultDark
            }
            store.settings.profiles[index].syncLegacyColorScheme()
        }
    }

    private func importScheme() {
        let panel = NSOpenPanel()
        if let type = UTType(filenameExtension: "itermcolors") {
            panel.allowedContentTypes = [type]
        }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var imported = try ColorScheme.fromITermColors(url: url)
            imported.origin = .user
            imported.name = ColorScheme.uniqueName(imported.name, avoiding: existingSchemeNames())
            store.settings.customSchemes.append(imported)
            setScheme(imported)
        } catch {
            schemeError = error.localizedDescription
        }
    }
}
