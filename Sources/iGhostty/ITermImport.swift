import Foundation

/// Importer for iTerm2's configuration formats:
/// - `com.googlecode.iterm2.plist` preferences ("New Bookmarks" array)
/// - Dynamic Profiles files ({"Profiles": [...]}, JSON or plist)
/// - any single profile dictionary using iTerm2's documented profile keys
enum ITermImport {
    static var defaultPreferencesPath: String {
        NSHomeDirectory() + "/Library/Preferences/com.googlecode.iterm2.plist"
    }

    static func importProfiles(from url: URL) throws -> [Profile] {
        let data = try Data(contentsOf: url)

        var root: Any?
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            root = plist
        } else if let json = try? JSONSerialization.jsonObject(with: data) {
            root = json
        }
        guard let dict = root as? [String: Any] else {
            throw GhosttyAppError.invalidITermConfig("file is not a plist or JSON dictionary")
        }

        let entries = (dict["New Bookmarks"] as? [[String: Any]])
            ?? (dict["Profiles"] as? [[String: Any]])
            ?? (dict["Name"] != nil ? [dict] : nil)
        guard let entries, !entries.isEmpty else {
            throw GhosttyAppError.invalidITermConfig("no profiles found — expected a \"New Bookmarks\" or \"Profiles\" array")
        }
        return entries.map { profile(from: $0) }
    }

    // MARK: Field mapping

    static func profile(from d: [String: Any]) -> Profile {
        var p = Profile()
        p.name = string(d, "Name") ?? "iTerm2 Import"

        // Command: "No"/"Login Shell" = login shell; "Yes"/"Custom Shell" = custom.
        switch string(d, "Custom Command") ?? "No" {
        case "Yes", "Custom Shell":
            let command = string(d, "Command") ?? ""
            let parts = command.split(separator: " ").map(String.init)
            p.customShellPath = parts.first ?? ""
            p.shellArguments = Array(parts.dropFirst())
            p.useLoginShell = false
        default:
            p.useLoginShell = true
        }

        // Working directory: "Yes" = custom, "Recycle" = reuse previous.
        switch string(d, "Custom Directory") ?? "No" {
        case "Yes":
            p.workingDirectory = .custom
            p.customWorkingDirectory = string(d, "Working Directory") ?? "~"
        case "Recycle":
            p.workingDirectory = .inherit
        default:
            p.workingDirectory = .home
        }

        if let font = string(d, "Normal Font") {
            let (name, size) = parseFont(font)
            p.fontName = name
            p.fontSize = size
        }

        if let cols = int(d, "Columns") { p.columns = max(20, cols) }
        if let rows = int(d, "Rows") { p.rows = max(5, rows) }
        if let lines = int(d, "Scrollback Lines") { p.scrollbackLines = max(0, lines) }
        if let unlimited = bool(d, "Unlimited Scrollback") { p.unlimitedScrollback = unlimited }

        // iTerm2 stores transparency as 0 = opaque; map that directly.
        if let transparency = double(d, "Transparency") {
            p.transparency = min(max(transparency, 0), 0.9)
        }
        if let blur = bool(d, "Blur") { p.blurEnabled = blur }
        if let blurRadius = double(d, "Blur Radius") { p.blurRadius = min(max(blurRadius, 0), 64) }

        // Cursor Type: 0 = underline, 1 = vertical bar, 2 = box.
        switch int(d, "Cursor Type") {
        case 0: p.cursorShape = .underline
        case 1: p.cursorShape = .bar
        default: p.cursorShape = .block
        }
        if let blink = bool(d, "Blinking Cursor") { p.cursorBlink = blink }

        // Option Key Sends: 0 = normal, 1 = meta, 2 = Esc+.
        if let option = int(d, "Option Key Sends") { p.optionAsMeta = option != 0 }
        if let mouse = bool(d, "Mouse Reporting") { p.mouseReporting = mouse }
        if let silence = bool(d, "Silence Bell") { p.audibleBell = !silence }
        if let visual = bool(d, "Visual Bell") { p.visualBell = visual }
        if let term = string(d, "Terminal Type") { p.termVariable = term }
        if let close = bool(d, "Close Sessions On End") {
            p.closeOnExit = close ? .always : .never
        }

        p.scheme = scheme(from: d, name: p.name)
        return p
    }

    static func scheme(from d: [String: Any], name: String) -> ColorScheme {
        let fallback = ColorScheme.builtIns[0]
        var ansi: [TermColor] = []
        var sawAny = false
        for i in 0..<16 {
            if let c = color(d, "Ansi \(i) Color") {
                ansi.append(c)
                sawAny = true
            } else {
                ansi.append(fallback.ansi[i])
            }
        }
        guard sawAny || color(d, "Background Color") != nil else { return fallback }

        let bg = color(d, "Background Color") ?? fallback.background
        let fg = color(d, "Foreground Color") ?? fallback.foreground
        return ColorScheme(
            name: "\(name) (iTerm2)",
            ansi: ansi,
            foreground: fg,
            background: bg,
            cursor: color(d, "Cursor Color") ?? fg,
            cursorText: color(d, "Cursor Text Color") ?? bg,
            selection: color(d, "Selection Color") ?? fallback.selection
        )
    }

    static func parseFont(_ value: String) -> (name: String, size: Double) {
        let parts = value.split(separator: " ")
        if parts.count >= 2, let size = Double(parts.last!) {
            return (parts.dropLast().joined(separator: " "), min(max(size, 6), 72))
        }
        return (value, 13)
    }

    // MARK: Plist/JSON value coercion

    private static func string(_ d: [String: Any], _ key: String) -> String? {
        d[key] as? String
    }

    private static func int(_ d: [String: Any], _ key: String) -> Int? {
        (d[key] as? NSNumber)?.intValue
    }

    private static func double(_ d: [String: Any], _ key: String) -> Double? {
        (d[key] as? NSNumber)?.doubleValue
    }

    private static func bool(_ d: [String: Any], _ key: String) -> Bool? {
        (d[key] as? NSNumber)?.boolValue
    }

    private static func color(_ d: [String: Any], _ key: String) -> TermColor? {
        guard let c = d[key] as? [String: Any],
              let r = (c["Red Component"] as? NSNumber)?.doubleValue,
              let g = (c["Green Component"] as? NSNumber)?.doubleValue,
              let b = (c["Blue Component"] as? NSNumber)?.doubleValue else { return nil }
        return TermColor(r: r, g: g, b: b)
    }
}
