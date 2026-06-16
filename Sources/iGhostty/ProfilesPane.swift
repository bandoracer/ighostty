import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Profiles list + editor

struct ProfilesPane: View {
    @EnvironmentObject var store: SettingsStore
    @State private var selectedID: UUID?
    @State private var importMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selectedID) {
                    ForEach(store.settings.profiles) { profile in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(nsColor: NSColor(profile.activeColorScheme.background)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
                                )
                                .frame(width: 14, height: 14)
                            Text(profile.name)
                                .lineLimit(1)
                            Spacer()
                            if profile.id == store.settings.defaultProfileID {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                                    .help("Default profile")
                            }
                        }
                        .tag(profile.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()
                HStack(spacing: 10) {
                    Button(action: addProfile) {
                        Image(systemName: "plus")
                    }
                    .help("Duplicate the selected profile")
                    Button(action: deleteSelected) {
                        Image(systemName: "minus")
                    }
                    .disabled(!canDeleteSelected)
                    .help("Delete the selected profile")
                    Menu {
                        Button("From iTerm2 Preferences") { importITerm(path: ITermImport.defaultPreferencesPath) }
                            .disabled(!FileManager.default.fileExists(atPath: ITermImport.defaultPreferencesPath))
                        Button("From File (plist / Dynamic Profiles JSON)…") { importITermFromPanel() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Import iTerm2 profiles")
                    Spacer()
                    Button("Set Default") {
                        if let selectedID { store.settings.defaultProfileID = selectedID }
                    }
                    .disabled(selectedID == nil || selectedID == store.settings.defaultProfileID)
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
            .frame(width: 230)
            .alert("iTerm2 Import", isPresented: .init(get: { importMessage != nil }, set: { _ in importMessage = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }

            Divider()

            if let binding = profileBinding(selectedID) {
                ProfileEditor(profile: binding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Select a profile to edit")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = store.settings.defaultProfileID }
        }
        .onReceive(NotificationCenter.default.publisher(for: .iGhosttySelectProfile)) { note in
            if let id = note.object as? UUID, store.settings.profiles.contains(where: { $0.id == id }) {
                selectedID = id
            }
        }
    }

    private var canDeleteSelected: Bool {
        selectedID != nil && store.settings.profiles.count > 1
    }

    private func profileBinding(_ id: UUID?) -> Binding<Profile>? {
        guard let id, store.settings.profiles.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                store.settings.profiles.first { $0.id == id } ?? .placeholder
            },
            set: { newValue in
                if let idx = store.settings.profiles.firstIndex(where: { $0.id == id }) {
                    store.settings.profiles[idx] = newValue
                }
            }
        )
    }

    private func addProfile() {
        var p = store.profile(withID: selectedID) ?? store.defaultProfile
        p.id = UUID()
        let baseNames = Set(store.settings.profiles.map(\.name))
        var i = 1
        var name = "\(p.name) Copy"
        while baseNames.contains(name) {
            i += 1
            name = "\(p.name) Copy \(i)"
        }
        p.name = name
        store.settings.profiles.append(p)
        selectedID = p.id
    }

    private func deleteSelected() {
        guard let id = selectedID, store.settings.profiles.count > 1 else { return }
        store.settings.profiles.removeAll { $0.id == id }
        if store.settings.defaultProfileID == id, let first = store.settings.profiles.first {
            store.settings.defaultProfileID = first.id
        }
        selectedID = store.settings.profiles.first?.id
    }

    private func importITermFromPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.propertyList, .json, .xml, .data]
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/iTerm2/DynamicProfiles", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importITerm(path: url.path)
    }

    private func importITerm(path: String) {
        do {
            let imported = try ITermImport.importProfiles(from: URL(fileURLWithPath: path))
            guard !imported.isEmpty else {
                importMessage = "No profiles found in that file."
                return
            }
            store.settings.profiles.append(contentsOf: imported)
            selectedID = imported.first?.id
            importMessage = "Imported \(imported.count) profile\(imported.count == 1 ? "" : "s"). Colors, fonts, command, working directory, scrollback, cursor, and bell settings come across."
        } catch {
            importMessage = error.localizedDescription
        }
    }
}

// MARK: - Profile editor

private enum ProfileSection: String, CaseIterable, Identifiable {
    case general = "General"
    case text = "Text"
    case colors = "Colors"
    case window = "Window"
    case terminal = "Terminal"
    var id: String { rawValue }
}

struct ProfileEditor: View {
    @Binding var profile: Profile
    @State private var section: ProfileSection

    init(profile: Binding<Profile>) {
        _profile = profile
        let remembered = UserDefaults.standard.string(forKey: "profileEditorSection") ?? ""
        _section = State(initialValue: ProfileSection(rawValue: remembered) ?? .general)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(ProfileSection.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .onChange(of: section) { newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: "profileEditorSection")
            }

            Divider()

            switch section {
            case .general: ProfileGeneralTab(profile: $profile)
            case .text: ProfileTextTab(profile: $profile)
            case .colors: ProfileColorsTab(profile: $profile)
            case .window: ProfileWindowTab(profile: $profile)
            case .terminal: ProfileTerminalTab(profile: $profile)
            }
        }
    }
}

// MARK: General tab

private struct ProfileGeneralTab: View {
    @Binding var profile: Profile

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $profile.name)
            }

            Section("Command") {
                Toggle("Login shell", isOn: $profile.useLoginShell)
                TextField("Shell", text: $profile.customShellPath, prompt: Text(defaultShellPath() + "  (default)"))
                TextField("Arguments", text: argumentsBinding, prompt: Text("none"))
                TextField("Initial command", text: $profile.initialCommand, prompt: Text("none"))
            }

            Section("Working Directory") {
                Picker("Start in", selection: $profile.workingDirectory) {
                    ForEach(WorkingDirectoryOption.allCases) { Text($0.label).tag($0) }
                }
                if profile.workingDirectory == .custom {
                    TextField("Directory", text: $profile.customWorkingDirectory)
                }
            }

            Section {
                TextEditor(text: $profile.environmentOverrides)
                    .font(.body.monospaced())
                    .frame(height: 88)
            } header: {
                Text("Environment Variables")
            } footer: {
                Text("One KEY=value per line. Lines starting with # are ignored.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var argumentsBinding: Binding<String> {
        Binding(
            get: { profile.shellArguments.joined(separator: " ") },
            set: { profile.shellArguments = $0.split(separator: " ").map(String.init) }
        )
    }
}

// MARK: Text tab

private struct ProfileTextTab: View {
    @Binding var profile: Profile

    var body: some View {
        Form {
            Section("Font") {
                Picker("Font", selection: $profile.fontName) {
                    Text("System Monospace (SF Mono)").tag("")
                    Divider()
                    ForEach(monospaceFontFamilies(), id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $profile.fontSize, in: 8...28, step: 1)
                        Text("\(Int(profile.fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Cursor") {
                Picker("Style", selection: $profile.cursorShape) {
                    ForEach(CursorShape.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Blink", isOn: $profile.cursorBlink)
            }

            Section("Preview") {
                SchemePairPreview(profile: profile)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Colors tab

private let ansiNames = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]

private struct ProfileColorsTab: View {
    @Binding var profile: Profile
    @EnvironmentObject var store: SettingsStore
    @State private var importError: String?
    @State private var schemeError: String?
    @State private var editingAppearance: AppearanceVariant = .dark
    @State private var browsingAppearance: AppearanceVariant?

    var body: some View {
        Form {
            Section {
                schemeChooser(for: .light)
                schemeChooser(for: .dark)
            } header: {
                Text("Schemes")
            } footer: {
                Text("Click a preview to browse themes. Match System swaps between these automatically; manual Light or Dark uses the matching scheme.")
                    .foregroundStyle(.secondary)
            }

            Section("Customize") {
                Picker("Edit", selection: $editingAppearance) {
                    ForEach(AppearanceVariant.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("Import iTerm2 Scheme (.itermcolors)…") { importScheme() }
            }

            Section("Manage Scheme") {
                selectedSchemeStatus
                HStack {
                    Button {
                        revertEditingScheme()
                    } label: {
                        Label("Revert", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!isEditingSchemeModified)

                    Button {
                        duplicateEditingScheme()
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                }

                HStack {
                    Button {
                        renameEditingScheme()
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .disabled(!isEditingSchemeUserCreated)

                    Button(role: .destructive) {
                        deleteEditingScheme()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(!isEditingSchemeUserCreated)
                }
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
        .alert("Import failed", isPresented: .init(get: { importError != nil }, set: { _ in importError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert("Scheme action failed", isPresented: .init(get: { schemeError != nil }, set: { _ in schemeError = nil })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(schemeError ?? "")
        }
        .sheet(item: $browsingAppearance) { appearance in
            ThemeBrowser(
                appearance: appearance,
                current: profile.colorScheme(for: appearance),
                customSchemes: store.settings.customSchemes,
                onApply: { setScheme($0, for: appearance) }
            )
        }
    }

    /// A clickable preview of the current scheme that opens the theme browser.
    /// Replaces the old flat dropdown of ~500 scheme names.
    private func schemeChooser(for appearance: AppearanceVariant) -> some View {
        let scheme = profile.colorScheme(for: appearance)
        return Button {
            browsingAppearance = appearance
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("\(appearance.label) mode")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(scheme.name)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    schemeBadge(isSchemeUserCreated(scheme) ? ColorSchemeOrigin.user.label : ColorSchemeOrigin.builtIn.label)
                    if isSchemeModified(scheme, for: appearance) {
                        schemeBadge("Modified")
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                SchemePreview(scheme: scheme, fontName: profile.fontName, fontSize: profile.fontSize)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Browse \(appearance.label.lowercased()) themes")
        .padding(.vertical, 2)
    }

    private var selectedSchemeStatus: some View {
        let scheme = profile.colorScheme(for: editingAppearance)
        return LabeledContent("Selected") {
            HStack(spacing: 6) {
                Text(scheme.name)
                    .lineLimit(1)
                schemeBadge(isSchemeUserCreated(scheme) ? ColorSchemeOrigin.user.label : ColorSchemeOrigin.builtIn.label)
                if isSchemeModified(scheme, for: editingAppearance) {
                    schemeBadge("Modified")
                }
            }
        }
    }

    private func schemeBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private func colorRow(_ label: String, _ keyPath: WritableKeyPath<ColorScheme, TermColor>) -> some View {
        ColorPicker(label, selection: colorBinding(keyPath), supportsOpacity: false)
    }

    private func colorBinding(_ keyPath: WritableKeyPath<ColorScheme, TermColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(profile.colorScheme(for: editingAppearance)[keyPath: keyPath])) },
            set: { newValue in
                mutateEditingScheme {
                    $0[keyPath: keyPath] = NSColor(newValue).termColor
                }
            }
        )
    }

    private func ansiBinding(_ index: Int) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(profile.colorScheme(for: editingAppearance).ansi[index])) },
            set: { newValue in
                mutateEditingScheme {
                    $0.ansi[index] = NSColor(newValue).termColor
                }
            }
        )
    }

    private func mutateEditingScheme(_ mutate: (inout ColorScheme) -> Void) {
        var scheme = profile.colorScheme(for: editingAppearance)
        mutate(&scheme)
        setScheme(scheme, for: editingAppearance)
    }

    private func setScheme(_ scheme: ColorScheme, for appearance: AppearanceVariant) {
        switch appearance {
        case .light:
            profile.lightScheme = scheme
        case .dark:
            profile.darkScheme = scheme
        }
        profile.syncLegacyColorScheme()
    }

    private var isEditingSchemeModified: Bool {
        isSchemeModified(profile.colorScheme(for: editingAppearance), for: editingAppearance)
    }

    private var isEditingSchemeUserCreated: Bool {
        isSchemeUserCreated(profile.colorScheme(for: editingAppearance))
    }

    private func canonicalScheme(for scheme: ColorScheme, appearance: AppearanceVariant) -> ColorScheme? {
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

    private func isSchemeModified(_ scheme: ColorScheme, for appearance: AppearanceVariant) -> Bool {
        guard let canonical = canonicalScheme(for: scheme, appearance: appearance) else { return false }
        return !scheme.hasSameColors(as: canonical)
    }

    private func isSchemeUserCreated(_ scheme: ColorScheme) -> Bool {
        scheme.origin == .user || customScheme(named: scheme.name) != nil
    }

    private func customScheme(named name: String) -> ColorScheme? {
        store.settings.customSchemes.first { $0.name == name }
    }

    private func customSchemeIndex(named name: String) -> Int? {
        store.settings.customSchemes.firstIndex { $0.name == name }
    }

    private func existingSchemeNames(excluding excluded: String? = nil) -> Set<String> {
        var names = Set(
            ColorScheme.builtIns(for: .light).map(\.name)
                + ColorScheme.builtIns(for: .dark).map(\.name)
                + store.settings.customSchemes.map(\.name)
        )
        if let excluded { names.remove(excluded) }
        return names
    }

    private func revertEditingScheme() {
        let scheme = profile.colorScheme(for: editingAppearance)
        guard let canonical = canonicalScheme(for: scheme, appearance: editingAppearance) else { return }
        setScheme(canonical, for: editingAppearance)
    }

    private func duplicateEditingScheme() {
        var duplicate = profile.colorScheme(for: editingAppearance)
        duplicate.origin = .user
        let baseName = duplicate.legacyCustomBaseName ?? duplicate.name
        duplicate.name = ColorScheme.uniqueName("\(baseName) Copy", avoiding: existingSchemeNames())
        store.settings.customSchemes.append(duplicate)
        setScheme(duplicate, for: editingAppearance)
    }

    private func renameEditingScheme() {
        let scheme = profile.colorScheme(for: editingAppearance)
        guard isSchemeUserCreated(scheme) else { return }

        let alert = NSAlert()
        alert.messageText = "Rename Color Scheme"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: scheme.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        renameUserScheme(named: scheme.name, to: field.stringValue)
    }

    private func renameUserScheme(named oldName: String, to proposedName: String) {
        let newName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            schemeError = "Color scheme names cannot be empty."
            return
        }
        guard !existingSchemeNames(excluding: oldName).contains(newName) else {
            schemeError = "A color scheme named “\(newName)” already exists."
            return
        }

        if let index = customSchemeIndex(named: oldName) {
            store.settings.customSchemes[index].name = newName
            store.settings.customSchemes[index].origin = .user
            renameUserSchemeReferences(named: oldName, to: newName)
        } else {
            var renamed = profile.colorScheme(for: editingAppearance)
            renamed.name = newName
            renamed.origin = .user
            setScheme(renamed, for: editingAppearance)
        }
    }

    private func renameUserSchemeReferences(named oldName: String, to newName: String) {
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

    private func deleteEditingScheme() {
        let scheme = profile.colorScheme(for: editingAppearance)
        guard isSchemeUserCreated(scheme) else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Color Scheme?"
        alert.informativeText = "Profiles using “\(scheme.name)” will switch back to the default scheme for each appearance."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let index = customSchemeIndex(named: scheme.name) {
            store.settings.customSchemes.remove(at: index)
        }
        resetUserSchemeReferences(named: scheme.name)
    }

    private func resetUserSchemeReferences(named name: String) {
        for index in store.settings.profiles.indices {
            if store.settings.profiles[index].lightScheme.name == name {
                store.settings.profiles[index].lightScheme = defaultScheme(for: .light)
            }
            if store.settings.profiles[index].darkScheme.name == name {
                store.settings.profiles[index].darkScheme = defaultScheme(for: .dark)
            }
            store.settings.profiles[index].syncLegacyColorScheme()
        }
    }

    private func defaultScheme(for appearance: AppearanceVariant) -> ColorScheme {
        switch appearance {
        case .light: return ColorScheme.defaultLight
        case .dark: return ColorScheme.defaultDark
        }
    }

    private func ansiGrid(range: Range<Int>, title: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                ForEach(range, id: \.self) { i in
                    ColorPicker("", selection: ansiBinding(i), supportsOpacity: false)
                        .labelsHidden()
                        .help(i < 8 ? ansiNames[i] : "Bright \(ansiNames[i - 8])")
                }
            }
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
            var scheme = try ColorScheme.fromITermColors(url: url)
            scheme.origin = .user
            scheme.name = ColorScheme.uniqueName(scheme.name, avoiding: existingSchemeNames())
            store.settings.customSchemes.append(scheme)
            setScheme(scheme, for: editingAppearance)
        } catch {
            importError = error.localizedDescription
        }
    }
}

// MARK: Window tab

private struct ProfileWindowTab: View {
    @Binding var profile: Profile

    var body: some View {
        Form {
            Section("Initial Size") {
                LabeledContent("Columns") {
                    HStack {
                        TextField("", value: $profile.columns, format: .number)
                            .labelsHidden()
                            .frame(width: 64)
                        Stepper("", value: $profile.columns, in: 40...400)
                            .labelsHidden()
                    }
                }
                LabeledContent("Rows") {
                    HStack {
                        TextField("", value: $profile.rows, format: .number)
                            .labelsHidden()
                            .frame(width: 64)
                        Stepper("", value: $profile.rows, in: 10...150)
                            .labelsHidden()
                    }
                }
            }

            Section("Transparency") {
                LabeledContent("Transparency") {
                    HStack {
                        Slider(value: $profile.transparency, in: 0...0.9)
                        Text("\(Int(profile.transparency * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle("Blur", isOn: $profile.blurEnabled)
                if profile.blurEnabled {
                    LabeledContent("Blur radius") {
                        HStack {
                            Slider(value: $profile.blurRadius, in: 0...64, step: 1)
                            Text("\(Int(profile.blurRadius))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                Toggle("Transparent title bar", isOn: $profile.transparentTitleBar)
                    .disabled(profile.transparency < 0.01)
                    .help("Off: keep the title bar opaque while the terminal content stays transparent.")
            }

            Section {
                LabeledContent("Padding") {
                    HStack {
                        Slider(value: $profile.padding, in: 0...24, step: 1)
                        Text("\(Int(profile.padding)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } footer: {
                Text("Transparency: 0% is opaque, higher is more see-through. Blur softens whatever shows through (turn it off for a clear glass look). Toggle all transparency app-wide with View ▸ Use Transparency (⌘U). New windows use the initial size; existing windows keep theirs.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Terminal tab

private struct ProfileTerminalTab: View {
    @Binding var profile: Profile

    var body: some View {
        Form {
            Section("Scrollback") {
                Toggle("Effectively unlimited (1M lines)", isOn: $profile.unlimitedScrollback)
                if !profile.unlimitedScrollback {
                    LabeledContent("Lines") {
                        TextField("", value: $profile.scrollbackLines, format: .number)
                            .labelsHidden()
                            .frame(width: 90)
                    }
                }
            }

            Section("Keyboard & Mouse") {
                Toggle("Option key acts as Meta (Esc+)", isOn: $profile.optionAsMeta)
                Toggle("Report mouse events to apps", isOn: $profile.mouseReporting)
            }

            Section("Shell Integration") {
                Picker("Mode", selection: $profile.shellIntegration) {
                    ForEach(ShellIntegrationMode.allCases) { Text($0.label).tag($0) }
                }
                TextField("Features", text: $profile.shellIntegrationFeatures, prompt: Text("cursor,path,title"))
                Text("Comma-separated Ghostty feature names. Add prompt to enable prompt marks and jump-to-prompt; omit it if prompt rows flicker during tab changes. SSH and sudo wrappers are opt-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Bell") {
                Toggle("Audible bell", isOn: $profile.audibleBell)
                Toggle("Visual bell (flash)", isOn: $profile.visualBell)
            }

            Section("Session") {
                TextField("TERM variable", text: $profile.termVariable, prompt: Text("xterm-ghostty"))
                Picker("When the shell exits", selection: $profile.closeOnExit) {
                    ForEach(CloseOnExit.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                TextEditor(text: $profile.ghosttyConfigOverrides)
                    .font(.body.monospaced())
                    .frame(height: 140)
                let issues = GhosttyConfigOverrides.parse(profile.ghosttyConfigOverrides).issues
                if !issues.isEmpty {
                    ForEach(issues) { issue in
                        Text("Line \(issue.line): \(issue.message)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Ghostty Config Overrides")
            } footer: {
                Text("One key = value per line. These are composed after native profile settings and may override them. Repeated keys such as keybind are preserved.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Scheme preview

struct SchemePairPreview: View {
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledPreview("Light", scheme: profile.lightScheme)
            labeledPreview("Dark", scheme: profile.darkScheme)
        }
    }

    private func labeledPreview(_ label: String, scheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            SchemePreview(scheme: scheme, fontName: profile.fontName, fontSize: profile.fontSize)
        }
    }
}

struct SchemePreview: View {
    let scheme: ColorScheme
    let fontName: String
    let fontSize: Double

    var body: some View {
        let font = Font(resolvedFont(name: fontName, size: min(max(fontSize, 10), 14)) as CTFont)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text("❯ ").foregroundColor(color(scheme.ansi[2]))
                Text("git ").foregroundColor(color(scheme.foreground))
                Text("status ").foregroundColor(color(scheme.ansi[4]))
                Text("--short").foregroundColor(color(scheme.ansi[3]))
            }
            HStack(spacing: 0) {
                Text(" M ").foregroundColor(color(scheme.ansi[1]))
                Text("Sources/iGhostty/main.swift").foregroundColor(color(scheme.foreground))
            }
            HStack(spacing: 0) {
                Text("?? ").foregroundColor(color(scheme.ansi[5]))
                Text("dist/  ").foregroundColor(color(scheme.foreground))
                Text("▍").foregroundColor(color(scheme.cursor))
            }
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(scheme.ansi[i]))
                        .frame(width: 14, height: 8)
                }
                ForEach(8..<16, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(scheme.ansi[i]))
                        .frame(width: 14, height: 8)
                }
            }
            .padding(.top, 4)
        }
        .font(font)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color(scheme.background))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func color(_ c: TermColor) -> Color {
        Color(red: c.r, green: c.g, blue: c.b)
    }
}
