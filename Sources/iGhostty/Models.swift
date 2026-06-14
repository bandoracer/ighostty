import AppKit

// MARK: - Colors

/// A plain sRGB color value (components 0...1) used throughout settings.
struct TermColor: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            r: Double((v >> 16) & 0xFF) / 255.0,
            g: Double((v >> 8) & 0xFF) / 255.0,
            b: Double(v & 0xFF) / 255.0
        )
    }

    var hexString: String {
        String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

// MARK: - Color schemes

struct ColorScheme: Codable, Equatable, Hashable, Identifiable {
    var name: String
    /// Exactly 16 entries: the standard + bright ANSI colors.
    var ansi: [TermColor]
    var foreground: TermColor
    var background: TermColor
    var cursor: TermColor
    var cursorText: TermColor
    var selection: TermColor

    var id: String { name }

    var isLight: Bool {
        (0.299 * background.r + 0.587 * background.g + 0.114 * background.b) > 0.6
    }
}

enum GhosttyAppError: LocalizedError {
    case invalidColorScheme(String)
    case invalidITermConfig(String)

    var errorDescription: String? {
        switch self {
        case .invalidColorScheme(let why): return "Could not import color scheme: \(why)"
        case .invalidITermConfig(let why): return "Could not import iTerm2 config: \(why)"
        }
    }
}

extension ColorScheme {
    static func make(_ name: String, bg: String, fg: String, cursor: String, selection: String, ansi: [String]) -> ColorScheme {
        ColorScheme(
            name: name,
            ansi: ansi.map { TermColor(hex: $0) },
            foreground: TermColor(hex: fg),
            background: TermColor(hex: bg),
            cursor: TermColor(hex: cursor),
            cursorText: TermColor(hex: bg),
            selection: TermColor(hex: selection)
        )
    }

    static let builtIns: [ColorScheme] = [
        .make("Tokyo Night", bg: "1A1B26", fg: "C0CAF5", cursor: "C0CAF5", selection: "283457",
              ansi: ["15161E", "F7768E", "9ECE6A", "E0AF68", "7AA2F7", "BB9AF7", "7DCFFF", "A9B1D6",
                     "414868", "F7768E", "9ECE6A", "E0AF68", "7AA2F7", "BB9AF7", "7DCFFF", "C0CAF5"]),
        .make("Dracula", bg: "282A36", fg: "F8F8F2", cursor: "F8F8F2", selection: "44475A",
              ansi: ["21222C", "FF5555", "50FA7B", "F1FA8C", "BD93F9", "FF79C6", "8BE9FD", "F8F8F2",
                     "6272A4", "FF6E6E", "69FF94", "FFFFA5", "D6ACFF", "FF92DF", "A4FFFF", "FFFFFF"]),
        .make("Catppuccin Mocha", bg: "1E1E2E", fg: "CDD6F4", cursor: "F5E0DC", selection: "585B70",
              ansi: ["45475A", "F38BA8", "A6E3A1", "F9E2AF", "89B4FA", "F5C2E7", "94E2D5", "BAC2DE",
                     "585B70", "F38BA8", "A6E3A1", "F9E2AF", "89B4FA", "F5C2E7", "94E2D5", "A6ADC8"]),
        .make("Nord", bg: "2E3440", fg: "D8DEE9", cursor: "D8DEE9", selection: "434C5E",
              ansi: ["3B4252", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "88C0D0", "E5E9F0",
                     "4C566A", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "8FBCBB", "ECEFF4"]),
        .make("One Dark", bg: "282C34", fg: "ABB2BF", cursor: "528BFF", selection: "3E4451",
              ansi: ["282C34", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "ABB2BF",
                     "5C6370", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "FFFFFF"]),
        .make("Gruvbox Dark", bg: "282828", fg: "EBDBB2", cursor: "EBDBB2", selection: "504945",
              ansi: ["282828", "CC241D", "98971A", "D79921", "458588", "B16286", "689D6A", "A89984",
                     "928374", "FB4934", "B8BB26", "FABD2F", "83A598", "D3869B", "8EC07C", "EBDBB2"]),
        .make("Solarized Dark", bg: "002B36", fg: "839496", cursor: "839496", selection: "073642",
              ansi: ["073642", "DC322F", "859900", "B58900", "268BD2", "D33682", "2AA198", "EEE8D5",
                     "002B36", "CB4B16", "586E75", "657B83", "839496", "6C71C4", "93A1A1", "FDF6E3"]),
        .make("Solarized Light", bg: "FDF6E3", fg: "657B83", cursor: "657B83", selection: "EEE8D5",
              ansi: ["073642", "DC322F", "859900", "B58900", "268BD2", "D33682", "2AA198", "EEE8D5",
                     "002B36", "CB4B16", "586E75", "657B83", "839496", "6C71C4", "93A1A1", "FDF6E3"]),
        .make("Classic", bg: "000000", fg: "BFBFBF", cursor: "BFBFBF", selection: "4D4D4D",
              ansi: ["000000", "CC0000", "00CC00", "CCCC00", "2666CC", "CC00CC", "00CCCC", "E5E5E5",
                     "4D4D4D", "FF0000", "00FF00", "FFFF00", "5C5CFF", "FF00FF", "00FFFF", "FFFFFF"]),
    ]

    /// Parses an iTerm2 `.itermcolors` property list.
    static func fromITermColors(url: URL) throws -> ColorScheme {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw GhosttyAppError.invalidColorScheme("not a property list")
        }
        func component(_ dict: [String: Any], _ key: String) -> Double? {
            (dict[key] as? NSNumber)?.doubleValue
        }
        func color(_ key: String) -> TermColor? {
            guard let d = plist[key] as? [String: Any],
                  let r = component(d, "Red Component"),
                  let g = component(d, "Green Component"),
                  let b = component(d, "Blue Component") else { return nil }
            return TermColor(r: r, g: g, b: b)
        }
        var ansi: [TermColor] = []
        for i in 0..<16 {
            guard let c = color("Ansi \(i) Color") else {
                throw GhosttyAppError.invalidColorScheme("missing Ansi \(i) Color")
            }
            ansi.append(c)
        }
        let bg = color("Background Color") ?? TermColor(hex: "000000")
        let fg = color("Foreground Color") ?? TermColor(hex: "BFBFBF")
        return ColorScheme(
            name: url.deletingPathExtension().lastPathComponent,
            ansi: ansi,
            foreground: fg,
            background: bg,
            cursor: color("Cursor Color") ?? fg,
            cursorText: color("Cursor Text Color") ?? bg,
            selection: color("Selection Color") ?? TermColor(hex: "4D4D4D")
        )
    }
}

// MARK: - Profile

enum CursorShape: String, Codable, CaseIterable, Identifiable {
    case block, underline, bar
    var id: String { rawValue }
    var label: String {
        switch self {
        case .block: return "Block"
        case .underline: return "Underline"
        case .bar: return "Bar"
        }
    }
}

enum WorkingDirectoryOption: String, Codable, CaseIterable, Identifiable {
    case home, inherit, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: return "Home directory"
        case .inherit: return "Reuse previous session’s directory"
        case .custom: return "Custom directory"
        }
    }
}

enum CloseOnExit: String, Codable, CaseIterable, Identifiable {
    case always, cleanExit, never
    var id: String { rawValue }
    var label: String {
        switch self {
        case .always: return "Close the pane"
        case .cleanExit: return "Close only on clean exit"
        case .never: return "Keep the pane open"
        }
    }
}

struct Profile: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    var name = "Default"

    // Command
    var useLoginShell = true
    var customShellPath = ""          // empty -> $SHELL
    var shellArguments: [String] = []
    var initialCommand = ""
    var workingDirectory: WorkingDirectoryOption = .inherit
    var customWorkingDirectory = "~"
    /// One KEY=VALUE per line.
    var environmentOverrides = ""

    // Text
    var fontName = ""                 // empty -> system monospace (SF Mono)
    var fontSize: Double = 13
    var cursorShape: CursorShape = .block
    var cursorBlink = true

    // Colors / window
    var scheme: ColorScheme = ColorScheme.builtIns[0]
    /// iTerm2 semantics: 0 = fully opaque, higher = more see-through.
    var transparency: Double = 0.0
    var blurEnabled: Bool = false
    /// Background blur radius (iTerm2's "Blur" radius), applied when transparent.
    var blurRadius: Double = 16
    /// When true (default), transparency also makes the title bar see-through;
    /// when false, the title bar stays opaque while the content is transparent.
    var transparentTitleBar: Bool = true
    var padding: Double = 8
    var columns = 120
    var rows = 30

    // Terminal behavior
    var scrollbackLines = 10_000
    var unlimitedScrollback = false
    var termVariable = "xterm-256color"
    var optionAsMeta = true
    var mouseReporting = true
    var audibleBell = true
    var visualBell = false
    var closeOnExit: CloseOnExit = .cleanExit

    static let placeholder = Profile(name: "—")

    var environmentDictionary: [String: String] {
        var out: [String: String] = [:]
        for line in environmentOverrides.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eq)...])
            if !key.isEmpty { out[key] = value }
        }
        return out
    }
}

// Tolerant decoding so settings files from older builds keep working, and the
// pre-iTerm2 `opacity`/`blur` fields migrate to `transparency`/`blurEnabled`.
// In an extension so the memberwise `Profile(...)` initializer is preserved.
extension Profile {
    private enum LegacyKeys: String, CodingKey {
        case opacity, blur
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile()
        func val<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        self.init()
        id = val(.id, d.id)
        name = val(.name, d.name)
        useLoginShell = val(.useLoginShell, d.useLoginShell)
        customShellPath = val(.customShellPath, d.customShellPath)
        shellArguments = val(.shellArguments, d.shellArguments)
        initialCommand = val(.initialCommand, d.initialCommand)
        workingDirectory = val(.workingDirectory, d.workingDirectory)
        customWorkingDirectory = val(.customWorkingDirectory, d.customWorkingDirectory)
        environmentOverrides = val(.environmentOverrides, d.environmentOverrides)
        fontName = val(.fontName, d.fontName)
        fontSize = val(.fontSize, d.fontSize)
        cursorShape = val(.cursorShape, d.cursorShape)
        cursorBlink = val(.cursorBlink, d.cursorBlink)
        scheme = val(.scheme, d.scheme)
        padding = val(.padding, d.padding)
        columns = val(.columns, d.columns)
        rows = val(.rows, d.rows)
        scrollbackLines = val(.scrollbackLines, d.scrollbackLines)
        unlimitedScrollback = val(.unlimitedScrollback, d.unlimitedScrollback)
        termVariable = val(.termVariable, d.termVariable)
        optionAsMeta = val(.optionAsMeta, d.optionAsMeta)
        mouseReporting = val(.mouseReporting, d.mouseReporting)
        audibleBell = val(.audibleBell, d.audibleBell)
        visualBell = val(.visualBell, d.visualBell)
        closeOnExit = val(.closeOnExit, d.closeOnExit)
        blurRadius = val(.blurRadius, d.blurRadius)
        transparentTitleBar = val(.transparentTitleBar, d.transparentTitleBar)

        // transparency: prefer the new key, else migrate legacy opacity (1 - opacity).
        let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
        if let t = (try? c.decodeIfPresent(Double.self, forKey: .transparency)) ?? nil {
            transparency = t
        } else if let op = (try? legacy?.decodeIfPresent(Double.self, forKey: .opacity)) ?? nil {
            transparency = min(max(1 - op, 0), 1)
        } else {
            transparency = d.transparency
        }
        if let b = (try? c.decodeIfPresent(Bool.self, forKey: .blurEnabled)) ?? nil {
            blurEnabled = b
        } else if let legacyBlur = (try? legacy?.decodeIfPresent(Bool.self, forKey: .blur)) ?? nil {
            // Old default blur=true only ever did anything when transparent; keep it.
            blurEnabled = legacyBlur && transparency > 0
        } else {
            blurEnabled = d.blurEnabled
        }
    }
}

// MARK: - App-level settings

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum HotkeyActivationMode: String, Codable, CaseIterable, Identifiable {
    case doubleTapModifier, shortcut
    var id: String { rawValue }
    var label: String {
        switch self {
        case .doubleTapModifier: return "Double-tap a modifier key"
        case .shortcut: return "Keyboard shortcut"
        }
    }
}

enum WindowStyle: String, Codable, CaseIterable, Identifiable {
    case regular, compact
    var id: String { rawValue }
    var label: String {
        switch self {
        case .regular: return "Standard title bar"
        case .compact: return "Compact — no title bar"
        }
    }
}

struct HotkeySettings: Codable, Equatable {
    var enabled = true
    var activationMode: HotkeyActivationMode = .doubleTapModifier
    var doubleTapModifier: UInt = NSEvent.ModifierFlags.control.rawValue
    var keyCode: UInt16 = 49 // Space
    var modifierFlags: UInt = NSEvent.ModifierFlags.option.rawValue
    var rows = 30
    var widthFraction: Double = 1.0
    var animationDuration: Double = 0.16
    var autoHide = true
    var followMouseScreen = true
    var profileID: UUID? = nil // nil -> default profile
    /// ⌘Q closes terminal windows but keeps the app (and the drop-down
    /// terminal) alive in the background; ⌥⌘Q quits completely.
    var keepAvailableInBackground = true

    init() {}

    // Lenient decoding so settings files written by older builds keep working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HotkeySettings()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? nil ?? d.enabled
        activationMode = (try? c.decodeIfPresent(HotkeyActivationMode.self, forKey: .activationMode)) ?? nil ?? d.activationMode
        doubleTapModifier = (try? c.decodeIfPresent(UInt.self, forKey: .doubleTapModifier)) ?? nil ?? d.doubleTapModifier
        keyCode = (try? c.decodeIfPresent(UInt16.self, forKey: .keyCode)) ?? nil ?? d.keyCode
        modifierFlags = (try? c.decodeIfPresent(UInt.self, forKey: .modifierFlags)) ?? nil ?? d.modifierFlags
        rows = (try? c.decodeIfPresent(Int.self, forKey: .rows)) ?? nil ?? d.rows
        widthFraction = (try? c.decodeIfPresent(Double.self, forKey: .widthFraction)) ?? nil ?? d.widthFraction
        animationDuration = (try? c.decodeIfPresent(Double.self, forKey: .animationDuration)) ?? nil ?? d.animationDuration
        autoHide = (try? c.decodeIfPresent(Bool.self, forKey: .autoHide)) ?? nil ?? d.autoHide
        followMouseScreen = (try? c.decodeIfPresent(Bool.self, forKey: .followMouseScreen)) ?? nil ?? d.followMouseScreen
        profileID = (try? c.decodeIfPresent(UUID.self, forKey: .profileID)) ?? nil
        keepAvailableInBackground = (try? c.decodeIfPresent(Bool.self, forKey: .keepAvailableInBackground)) ?? nil ?? d.keepAvailableInBackground
    }
}

struct UISettings: Codable, Equatable {
    var theme: AppTheme = .system
    var windowStyle: WindowStyle = .regular
    var desaturateInactivePanes = true
    var desaturationAmount: Double = 0.15
    var copyOnSelect = false
    var confirmQuit = true
    var useMetalRenderer = true
    /// iTerm2's View > Use Transparency (⌘U): when off, profile opacity is
    /// ignored and every terminal renders fully opaque.
    var useTransparency = true

    init() {}

    private enum LegacyKeys: String, CodingKey {
        case dimInactivePanes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try? decoder.container(keyedBy: LegacyKeys.self)
        let d = UISettings()
        theme = (try? c.decodeIfPresent(AppTheme.self, forKey: .theme)) ?? nil ?? d.theme
        windowStyle = (try? c.decodeIfPresent(WindowStyle.self, forKey: .windowStyle)) ?? nil ?? d.windowStyle
        desaturateInactivePanes = (try? c.decodeIfPresent(Bool.self, forKey: .desaturateInactivePanes))
            ?? nil
            ?? ((try? legacy?.decodeIfPresent(Bool.self, forKey: .dimInactivePanes)) ?? nil)
            ?? d.desaturateInactivePanes
        desaturationAmount = (try? c.decodeIfPresent(Double.self, forKey: .desaturationAmount)) ?? nil ?? d.desaturationAmount
        copyOnSelect = (try? c.decodeIfPresent(Bool.self, forKey: .copyOnSelect)) ?? nil ?? d.copyOnSelect
        confirmQuit = (try? c.decodeIfPresent(Bool.self, forKey: .confirmQuit)) ?? nil ?? d.confirmQuit
        useMetalRenderer = (try? c.decodeIfPresent(Bool.self, forKey: .useMetalRenderer)) ?? nil ?? d.useMetalRenderer
        useTransparency = (try? c.decodeIfPresent(Bool.self, forKey: .useTransparency)) ?? nil ?? d.useTransparency
    }
}

struct AppSettings: Codable, Equatable {
    var profiles: [Profile]
    var defaultProfileID: UUID
    var hotkey = HotkeySettings()
    var ui = UISettings()
    var customSchemes: [ColorScheme] = []

    static func freshDefault() -> AppSettings {
        var main = Profile(name: "Default")
        main.scheme = ColorScheme.builtIns[0] // Tokyo Night

        var dracula = Profile(name: "Dracula")
        dracula.scheme = ColorScheme.builtIns[1]

        var light = Profile(name: "Solarized Light")
        light.scheme = ColorScheme.builtIns[7]

        return AppSettings(profiles: [main, dracula, light], defaultProfileID: main.id)
    }
}
