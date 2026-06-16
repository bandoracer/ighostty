import AppKit
import GhosttyTerminal
import GhosttyTheme

enum GhosttyResources {
    static var rootURL: URL? {
        let fm = FileManager.default
        let bundleCandidate = Bundle.main.resourceURL?.appendingPathComponent("GhosttyResources", isDirectory: true)
        if let bundleCandidate, fm.fileExists(atPath: bundleCandidate.path) {
            return bundleCandidate
        }
        let sourceCandidate = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent("Support/GhosttyResources", isDirectory: true)
        if fm.fileExists(atPath: sourceCandidate.path) {
            return sourceCandidate
        }
        return nil
    }

    static var resourcesDir: URL? {
        rootURL?.appendingPathComponent("share/ghostty", isDirectory: true)
    }

    static var terminfoDir: URL? {
        rootURL?.appendingPathComponent("share/terminfo", isDirectory: true)
    }

    static var binDir: URL? {
        rootURL?.appendingPathComponent("bin", isDirectory: true)
    }

    static var terminfoSourceURL: URL? {
        terminfoDir?.appendingPathComponent("ghostty.terminfo")
    }

    static var validationIssue: String? {
        let fm = FileManager.default
        guard let rootURL else { return "GhosttyResources is not bundled." }
        guard let resourcesDir, fm.fileExists(atPath: resourcesDir.appendingPathComponent("shell-integration").path) else {
            return "Missing Ghostty shell integration resources under \(rootURL.path)."
        }
        guard let terminfoSourceURL, fm.fileExists(atPath: terminfoSourceURL.path) else {
            return "Missing Ghostty terminfo source under \(rootURL.path)."
        }
        guard let terminfoDir,
              fm.fileExists(atPath: terminfoDir.appendingPathComponent("78/xterm-ghostty").path) else {
            return "Missing compiled xterm-ghostty terminfo entry under \(rootURL.path)."
        }
        return nil
    }
}

enum ShellIntegrationMode: String, Codable, CaseIterable, Identifiable {
    case detect
    case none
    case bash
    case elvish
    case fish
    case nushell
    case zsh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .detect: return "Detect automatically"
        case .none: return "Disabled"
        case .bash: return "bash"
        case .elvish: return "elvish"
        case .fish: return "fish"
        case .nushell: return "nushell"
        case .zsh: return "zsh"
        }
    }

    var ghosttyValue: String {
        rawValue
    }
}

enum AutomationPermission: String, Codable, CaseIterable, Identifiable {
    case ask
    case allow
    case deny

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ask: return "Ask"
        case .allow: return "Allow"
        case .deny: return "Deny"
        }
    }
}

struct GhosttyConfigIssue: Identifiable, Equatable {
    let line: Int
    let message: String
    var id: String { "\(line):\(message)" }
}

enum GhosttyConfigOverrides {
    static func parse(_ text: String) -> (entries: [(key: String, value: String)], issues: [GhosttyConfigIssue]) {
        var entries: [(key: String, value: String)] = []
        var issues: [GhosttyConfigIssue] = []

        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = offset + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let eq = trimmed.firstIndex(of: "=") else {
                issues.append(.init(line: lineNumber, message: "Expected key = value."))
                continue
            }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key.isEmpty {
                issues.append(.init(line: lineNumber, message: "Missing key before '='."))
                continue
            }
            if value.isEmpty {
                issues.append(.init(line: lineNumber, message: "Missing value after '='."))
                continue
            }
            entries.append((String(key), String(value)))
        }

        return (entries, issues)
    }
}

struct GhosttyShellLaunch {
    var executable: String
    var args: [String]
    var execName: String?
}

enum GhosttyShellIntegration {
    static func configure(
        shellPath: String,
        args: [String],
        loginShellName: String?,
        profile: Profile,
        environment env: inout [String: String]
    ) -> GhosttyShellLaunch {
        let term = profile.termVariable.trimmingCharacters(in: .whitespacesAndNewlines)
        env["TERM"] = term.isEmpty ? TerminalTerm.ghostty : term
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "iGhostty"
        env["TERM_PROGRAM_VERSION"] = appVersion

        if let resourcesDir = GhosttyResources.resourcesDir {
            env["GHOSTTY_RESOURCES_DIR"] = resourcesDir.path
        }
        if let terminfoDir = GhosttyResources.terminfoDir {
            env["TERMINFO"] = terminfoDir.path
        }
        if let binDir = GhosttyResources.binDir {
            env["GHOSTTY_BIN_DIR"] = binDir.path
        }

        let features = effectiveFeatures(profile.shellIntegrationFeatures, cursorBlink: profile.cursorBlink)
        if !features.isEmpty {
            env["GHOSTTY_SHELL_FEATURES"] = features
        } else {
            env.removeValue(forKey: "GHOSTTY_SHELL_FEATURES")
        }
        if promptMarksEnabled(profile.shellIntegrationFeatures) {
            env.removeValue(forKey: "IGHOSTTY_DISABLE_PROMPT_MARKS")
        } else {
            env["IGHOSTTY_DISABLE_PROMPT_MARKS"] = "1"
        }

        guard profile.shellIntegration != .none,
              let resourcesDir = GhosttyResources.resourcesDir else {
            return GhosttyShellLaunch(executable: shellPath, args: args, execName: loginShellName)
        }

        let shell = resolvedShell(profile.shellIntegration, shellPath: shellPath)
        switch shell {
        case .zsh:
            let integrationDir = resourcesDir.appendingPathComponent("shell-integration/zsh", isDirectory: true)
            if FileManager.default.fileExists(atPath: integrationDir.path) {
                if let old = env["ZDOTDIR"] { env["GHOSTTY_ZSH_ZDOTDIR"] = old }
                env["ZDOTDIR"] = integrationDir.path
            }
            return GhosttyShellLaunch(executable: shellPath, args: args, execName: loginShellName)

        case .fish, .elvish:
            prependXDGDataDir(resourcesDir.appendingPathComponent("shell-integration", isDirectory: true), env: &env)
            return GhosttyShellLaunch(executable: shellPath, args: args, execName: loginShellName)

        case .nushell:
            prependXDGDataDir(resourcesDir.appendingPathComponent("shell-integration", isDirectory: true), env: &env)
            if args.contains(where: { $0 == "-c" || $0 == "--command" || $0 == "--lsp" }) {
                return GhosttyShellLaunch(executable: shellPath, args: args, execName: loginShellName)
            }
            return GhosttyShellLaunch(
                executable: shellPath,
                args: ["--execute", "use ghostty *"] + args,
                execName: loginShellName
            )

        case .bash:
            if shellPath == "/bin/bash" || args.contains(where: { $0 == "-c" || $0.contains("c") && $0.hasPrefix("-") && !$0.hasPrefix("--") }) {
                return GhosttyShellLaunch(executable: shellPath, args: args, execName: loginShellName)
            }
            let script = resourcesDir.appendingPathComponent("shell-integration/bash/ghostty.bash")
            guard FileManager.default.fileExists(atPath: script.path) else {
                return GhosttyShellLaunch(executable: shellPath, args: args, execName: loginShellName)
            }
            if let old = env["ENV"] { env["GHOSTTY_BASH_ENV"] = old }
            env["ENV"] = script.path
            env["GHOSTTY_BASH_INJECT"] = "1"
            return GhosttyShellLaunch(executable: shellPath, args: ["--posix"] + args, execName: loginShellName)

        case .detect, .none:
            return GhosttyShellLaunch(executable: shellPath, args: args, execName: loginShellName)
        }
    }

    private static func resolvedShell(_ mode: ShellIntegrationMode, shellPath: String) -> ShellIntegrationMode {
        if mode != .detect { return mode }
        switch (shellPath as NSString).lastPathComponent {
        case "bash": return .bash
        case "elvish": return .elvish
        case "fish": return .fish
        case "nu": return .nushell
        case "zsh": return .zsh
        default: return .none
        }
    }

    private static func prependXDGDataDir(_ url: URL, env: inout [String: String]) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        env["GHOSTTY_SHELL_INTEGRATION_XDG_DIR"] = url.path
        let current = env["XDG_DATA_DIRS"] ?? "/usr/local/share:/usr/share"
        let parts = current.split(separator: ":").map(String.init)
        if parts.contains(url.path) {
            env["XDG_DATA_DIRS"] = current
        } else {
            env["XDG_DATA_DIRS"] = ([url.path] + parts).joined(separator: ":")
        }
    }

    static func effectiveFeatures(_ raw: String, cursorBlink: Bool) -> String {
        normalizeFeatures(raw) { cursorBlink ? "cursor:blink" : "cursor:steady" }
    }

    static func canonicalFeatureText(_ raw: String) -> String {
        normalizeFeatures(raw) { "cursor" }
    }

    static func ghosttyConfigFeatures(_ raw: String, cursorBlink: Bool) -> String {
        let features = effectiveFeatures(raw, cursorBlink: cursorBlink)
        return featureItems(features)
            .filter { !isIGhosttyOnlyFeature($0) }
            .joined(separator: ",")
    }

    static func promptMarksEnabled(_ raw: String) -> Bool {
        featureItems(raw).contains { isPromptFeature($0) }
    }

    private static func normalizeFeatures(_ raw: String, cursorReplacement: () -> String) -> String {
        var seen: Set<String> = []
        var normalized: [String] = []

        for item in featureItems(raw) {
            let key = item.lowercased()
            if key == "cursor" || key.hasPrefix("cursor:") {
                if seen.insert("cursor").inserted {
                    normalized.append(cursorReplacement())
                }
            } else if seen.insert(key).inserted {
                normalized.append(item)
            }
        }

        return normalized.joined(separator: ",")
    }

    private static func featureItems(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isIGhosttyOnlyFeature(_ feature: String) -> Bool {
        isPromptFeature(feature)
    }

    private static func isPromptFeature(_ feature: String) -> Bool {
        switch feature.lowercased() {
        case "prompt", "prompt-mark", "prompt-marks":
            return true
        default:
            return false
        }
    }
}

extension ColorScheme {
    // Computed once and cached: the catalog is ~485 themes and was previously
    // rebuilt on every access (e.g. every settings render / search keystroke).
    static let ghosttyCatalogLight: [ColorScheme] = ghosttyCatalog.filter(\.isLight)

    static let ghosttyCatalogDark: [ColorScheme] = ghosttyCatalog.filter { !$0.isLight }

    private static let ghosttyCatalog: [ColorScheme] =
        GhosttyThemeCatalog.allThemes.compactMap { ColorScheme(ghosttyTheme: $0) }

    init?(ghosttyTheme theme: GhosttyThemeDefinition) {
        let defaultANSI = ColorScheme.defaultDark.ansi
        let ansi = (0..<16).map { index in
            if let hex = theme.palette[index] {
                return TermColor(hex: hex)
            }
            return index < defaultANSI.count ? defaultANSI[index] : TermColor(hex: "000000")
        }
        guard ansi.count == 16 else { return nil }
        self.init(
            name: theme.name,
            ansi: ansi,
            foreground: TermColor(hex: theme.foreground),
            background: TermColor(hex: theme.background),
            cursor: TermColor(hex: theme.cursorColor ?? theme.foreground),
            cursorText: TermColor(hex: theme.cursorText ?? theme.background),
            selection: TermColor(hex: theme.selectionBackground ?? theme.foreground)
        )
    }
}

extension TerminalConfiguration.Builder {
    mutating func applyGhosttyOverrides(_ text: String) {
        for entry in GhosttyConfigOverrides.parse(text).entries {
            withCustom(entry.key, entry.value)
        }
    }
}
