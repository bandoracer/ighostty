import AppKit
import Carbon.HIToolbox
import Darwin

// MARK: - Color bridging

extension NSColor {
    convenience init(_ c: TermColor) {
        self.init(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    var termColor: TermColor {
        let c = usingColorSpace(.sRGB) ?? self
        return TermColor(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
    }
}

// MARK: - Fonts

func resolvedFont(name: String, size: CGFloat) -> NSFont {
    let clamped = min(max(size, 6), 72)
    if !name.isEmpty, let f = NSFont(name: name, size: clamped) {
        return f
    }
    return NSFont.monospacedSystemFont(ofSize: clamped, weight: .regular)
}

func monospaceFontFamilies() -> [String] {
    NSFontManager.shared.availableFontFamilies.filter { family in
        guard let f = NSFont(name: family, size: 12) else { return false }
        return f.isFixedPitch
    }.sorted()
}

func terminalCellSize(font: NSFont) -> NSSize {
    let w = ceil(("W" as NSString).size(withAttributes: [.font: font]).width)
    let h = ceil(font.ascender - font.descender + font.leading)
    return NSSize(width: max(w, 1), height: max(h, 1))
}

func preferredWindowCornerRadius() -> CGFloat {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    if version.majorVersion >= 27 {
        return 16
    }
    return 12
}

// MARK: - Paths & processes

extension String {
    var expandingTilde: String { (self as NSString).expandingTildeInPath }
    var abbreviatingTilde: String { (self as NSString).abbreviatingWithTildeInPath }
}

/// True when the process has child processes — i.e. the shell is actually
/// running something, not sitting at an idle prompt. Used to decide whether
/// closing/quitting deserves a confirmation, like iTerm2's "jobs running" check.
func processHasChildren(pid: pid_t) -> Bool {
    guard pid > 0 else { return false }
    let PROC_PPID_ONLY: UInt32 = 6
    var pids = [pid_t](repeating: 0, count: 64)
    let bytes = pids.withUnsafeMutableBytes { buffer -> Int32 in
        proc_listpids(PROC_PPID_ONLY, UInt32(pid), buffer.baseAddress, Int32(buffer.count))
    }
    guard bytes > 0 else { return false }
    let count = Int(bytes) / MemoryLayout<pid_t>.stride
    return pids.prefix(count).contains { $0 > 0 }
}

/// Working directory of a live process, via libproc (no shell integration needed).
func processCurrentDirectory(pid: pid_t) -> String? {
    guard pid > 0 else { return nil }
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
    let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
    guard ret > 0 else { return nil }
    let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) { ptr -> String in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
    }
    return path.isEmpty ? nil : path
}

func defaultShellPath() -> String {
    if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
        return shell
    }
    if let pw = getpwuid(getuid()), let shell = pw.pointee.pw_shell {
        let s = String(cString: shell)
        if !s.isEmpty { return s }
    }
    return "/bin/zsh"
}

/// Where a new session should start, honoring the profile's working-directory option.
func startDirectory(for profile: Profile, inheritingFrom session: TerminalSessionView?) -> String {
    switch profile.workingDirectory {
    case .home:
        return NSHomeDirectory()
    case .custom:
        let p = profile.customWorkingDirectory.expandingTilde
        return FileManager.default.fileExists(atPath: p) ? p : NSHomeDirectory()
    case .inherit:
        return session?.currentWorkingDirectory ?? NSHomeDirectory()
    }
}

// MARK: - Key combos

let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

private let keyCodeNames: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
    11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
    18: "1", 19: "2", 20: "3", 21: "4", 22: "5", 23: "6", 26: "7", 28: "8", 25: "9", 29: "0",
    27: "-", 24: "=", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
    46: "M", 47: ".", 50: "`",
    36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
    123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
    101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
]

func keyComboDisplayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
    var s = ""
    if modifiers.contains(.control) { s += "⌃" }
    if modifiers.contains(.option) { s += "⌥" }
    if modifiers.contains(.shift) { s += "⇧" }
    if modifiers.contains(.command) { s += "⌘" }
    s += keyCodeNames[keyCode] ?? "Key \(keyCode)"
    return s
}

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if flags.contains(.command) { m |= UInt32(cmdKey) }
    if flags.contains(.option) { m |= UInt32(optionKey) }
    if flags.contains(.control) { m |= UInt32(controlKey) }
    if flags.contains(.shift) { m |= UInt32(shiftKey) }
    return m
}

// MARK: - Misc

let appVersion = "1.0.0"

func currentAppearanceVariant() -> AppearanceVariant {
    switch SettingsStore.shared.settings.ui.theme {
    case .light:
        return .light
    case .dark:
        return .dark
    case .system:
        return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

/// Background alpha for a profile, honoring the global View > Use Transparency
/// toggle. iTerm2 stores transparency (0 = opaque); alpha = 1 - transparency.
func effectiveOpacity(for profile: Profile) -> Double {
    guard SettingsStore.shared.settings.ui.useTransparency else { return 1.0 }
    return min(max(1.0 - profile.transparency, 0.0), 1.0)
}

/// Window background-blur radius for a profile: 0 unless it is transparent,
/// blur is on, and the global transparency toggle is enabled.
func effectiveBlurRadius(for profile: Profile) -> Int {
    guard SettingsStore.shared.settings.ui.useTransparency,
          profile.blurEnabled, profile.transparency > 0.001 else { return 0 }
    return Int(min(max(profile.blurRadius, 0), 64).rounded())
}
